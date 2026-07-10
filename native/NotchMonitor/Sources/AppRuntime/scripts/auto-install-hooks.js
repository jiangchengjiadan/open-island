#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

const repoRoot = path.resolve(__dirname, '..');
const nodePath = process.execPath;
const hookScript = path.join(repoRoot, 'bridge', 'hook.js');
const claudeSettingsPath = path.join(process.env.HOME, '.claude', 'settings.json');
const codexConfigPath = path.join(process.env.HOME, '.codex', 'config.toml');
const codexHooksPath = path.join(process.env.HOME, '.codex', 'hooks.json');
const installCodexBridgeHooks = process.env.NOTCH_MONITOR_ENABLE_CODEX_HOOKS === '1';

const claudeCommand = `${nodePath} ${hookScript} event claude`;
const codexCommand = `${nodePath} ${hookScript} event codex`;

const matcherEvents = ['PreToolUse', 'PostToolUse', 'Notification'];
const passiveEvents = ['SessionStart', 'SessionEnd', 'Stop', 'SubagentStart', 'SubagentStop', 'UserPromptSubmit'];
const codexEvents = ['SessionStart', 'SessionEnd', 'Stop', 'UserPromptSubmit', 'PreToolUse', 'PostToolUse', 'Notification'];

function ensureDir(filePath) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
}

function backupFile(filePath) {
  if (!fs.existsSync(filePath)) return;
  const backupPath = `${filePath}.backup.${new Date().toISOString().replace(/[:]/g, '-')}`;
  fs.copyFileSync(filePath, backupPath);
}

function readJson(filePath, fallback) {
  if (!fs.existsSync(filePath)) return fallback;
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function writeJson(filePath, value) {
  ensureDir(filePath);
  fs.writeFileSync(filePath, JSON.stringify(value, null, 2));
}

/**
 * 移除由 Open Island 管理的旧 hook，避免重复注入或遗留失效命令。
 */
function stripManagedEntries(entries) {
  return (entries || []).filter((entry) => {
    if (typeof entry === 'string') {
      return !entry.includes('bridge/hook.js') && !entry.includes('.vibe-island/bin/vibe-island-bridge');
    }

    if (!entry || !Array.isArray(entry.hooks)) return true;

    const nextHooks = entry.hooks.filter((hook) => {
      const hookCommand = hook.command || '';
      return !hookCommand.includes('bridge/hook.js') && !hookCommand.includes('.vibe-island/bin/vibe-island-bridge');
    });

    if (nextHooks.length === entry.hooks.length) {
      return true;
    }

    if (nextHooks.length === 0) {
      return false;
    }

    entry.hooks = nextHooks;
    return true;
  });
}

function managedCommandEntry(command, matcher) {
  const hook = {
    command,
    type: 'command',
    timeout: 86400,
  };

  return matcher
    ? { matcher, hooks: [hook] }
    : { hooks: [hook] };
}

function installClaudeHooks() {
  const settings = readJson(claudeSettingsPath, {});
  settings.hooks = settings.hooks || {};

  if (Object.prototype.hasOwnProperty.call(settings.hooks, 'beforeStart')) {
    delete settings.hooks.beforeStart;
  }

  for (const [eventName, entries] of Object.entries(settings.hooks)) {
    settings.hooks[eventName] = stripManagedEntries(entries);
  }

  for (const eventName of matcherEvents) {
    settings.hooks[eventName] = settings.hooks[eventName] || [];
    settings.hooks[eventName].unshift(managedCommandEntry(claudeCommand, '*'));
  }

  for (const eventName of passiveEvents) {
    settings.hooks[eventName] = settings.hooks[eventName] || [];
    settings.hooks[eventName].unshift(managedCommandEntry(claudeCommand));
  }

  backupFile(claudeSettingsPath);
  writeJson(claudeSettingsPath, settings);
}

/**
 * 只有在显式开启 Codex bridge hooks 时才写入 codex_hooks feature，避免修改无关用户配置。
 */
function ensureCodexHooksFeature() {
  ensureDir(codexConfigPath);
  const content = fs.existsSync(codexConfigPath) ? fs.readFileSync(codexConfigPath, 'utf8') : '';
  if (content.includes('[features]') && content.includes('codex_hooks = true')) return;

  let nextContent = content.trimEnd();
  if (!nextContent.includes('[features]')) {
    nextContent += '\n\n[features]\n';
  } else if (!nextContent.endsWith('\n')) {
    nextContent += '\n';
  }

  if (!nextContent.includes('codex_hooks = true')) {
    nextContent += 'codex_hooks = true\n';
  }

  backupFile(codexConfigPath);
  fs.writeFileSync(codexConfigPath, `${nextContent.endsWith('\n') ? nextContent : `${nextContent}\n`}`);
}

/**
 * 安装或清理 Codex hooks。默认保留 wrapper 监控，只有显式 opt-in 才注入 bridge hooks。
 */
function installCodexHooks() {
  const config = readJson(codexHooksPath, { hooks: {} });
  config.hooks = config.hooks || {};

  for (const [eventName, entries] of Object.entries(config.hooks)) {
    const filteredEntries = stripManagedEntries(entries);
    if (filteredEntries.length > 0) {
      config.hooks[eventName] = filteredEntries;
    } else {
      delete config.hooks[eventName];
    }
  }

  if (installCodexBridgeHooks) {
    for (const eventName of codexEvents) {
      config.hooks[eventName] = config.hooks[eventName] || [];
      const needsMatcher = matcherEvents.includes(eventName);
      config.hooks[eventName].unshift(managedCommandEntry(codexCommand, needsMatcher ? '*' : undefined));
    }
  }

  backupFile(codexHooksPath);
  writeJson(codexHooksPath, config);
}

function main() {
  installClaudeHooks();
  console.log('Installed NotchMonitor hooks for Claude');

  if (installCodexBridgeHooks) {
    ensureCodexHooksFeature();
  }
  installCodexHooks();
  console.log(
    installCodexBridgeHooks
      ? 'Installed NotchMonitor hooks for Codex'
      : 'Kept Codex bridge hooks disabled by default; wrapper-based session monitoring remains enabled'
  );
}

main();
