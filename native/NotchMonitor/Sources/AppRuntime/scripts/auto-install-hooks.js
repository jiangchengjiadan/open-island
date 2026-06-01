#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

function resolveRepoRoot() {
  const sourceRepoRoot = path.resolve(__dirname, '..', '..', '..', '..', '..');
  if (fs.existsSync(path.join(sourceRepoRoot, 'bridge', 'hook.js'))) {
    return sourceRepoRoot;
  }
  return path.resolve(__dirname, '..');
}

const repoRoot = resolveRepoRoot();
const nodePath = process.execPath;
const hookScript = path.join(repoRoot, 'bridge', 'hook.js');
const claudeSettingsPath = path.join(process.env.HOME, '.claude', 'settings.json');
const cursorHooksPath = path.join(process.env.HOME, '.cursor', 'hooks.json');
const geminiSettingsPath = path.join(process.env.HOME, '.gemini', 'settings.json');
const qoderSettingsPath = path.join(process.env.HOME, '.qoder', 'settings.json');
const codexConfigPath = path.join(process.env.HOME, '.codex', 'config.toml');
const codexHooksPath = path.join(process.env.HOME, '.codex', 'hooks.json');

const claudeCommand = `${nodePath} ${hookScript} event claude`;
const cursorCommand = `${nodePath} ${hookScript} event cursor`;
const geminiCommand = `${nodePath} ${hookScript} event gemini`;
const qoderCommand = `${nodePath} ${hookScript} event qoder`;
const codexCommand = `${nodePath} ${hookScript} event codex`;

const matcherEvents = ['PreToolUse', 'PostToolUse', 'Notification'];
const passiveEvents = ['SessionStart', 'SessionEnd', 'Stop', 'SubagentStart', 'SubagentStop', 'UserPromptSubmit'];
const cursorEvents = ['beforeSubmitPrompt', 'beforeShellExecution', 'beforeMCPExecution', 'beforeReadFile', 'afterFileEdit', 'stop'];
const geminiEvents = ['SessionStart', 'SessionEnd', 'BeforeAgent', 'AfterAgent', 'Notification'];
const codexEvents = ['SessionStart', 'SessionEnd', 'Stop', 'UserPromptSubmit', 'PreToolUse', 'PostToolUse', 'Notification'];
const codexMatcherEvents = ['PreToolUse'];

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

function filterManagedEntries(entries, command) {
  return (entries || []).filter((entry) => {
    if (typeof entry === 'string') {
      return !entry.includes('bridge/hook.js') && !entry.includes('.vibe-island/bin/vibe-island-bridge');
    }

    if (!entry || !Array.isArray(entry.hooks)) return true;

    const nextHooks = entry.hooks.filter((hook) => {
      const hookCommand = hook.command || '';
      return !hookCommand.includes('bridge/hook.js') && !hookCommand.includes('.vibe-island/bin/vibe-island-bridge');
    });

    entry.hooks = nextHooks;
    return nextHooks.length > 0;
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

function dedupeHookEntries(entries) {
  const seen = new Set();
  const result = [];

  for (const entry of entries || []) {
    if (!entry || typeof entry !== 'object') {
      continue;
    }

    const matcher = typeof entry.matcher === 'string' ? entry.matcher : '';
    const hooks = Array.isArray(entry.hooks) ? entry.hooks : [];
    const key = JSON.stringify({
      matcher,
      hooks: hooks.map((hook) => ({
        command: hook?.command || '',
        type: hook?.type || '',
        timeout: hook?.timeout || 0,
      })),
    });

    if (seen.has(key)) continue;
    seen.add(key);
    result.push(entry);
  }

  return result;
}

function isManagedHookCommand(command) {
  return typeof command === 'string'
    && (command.includes('bridge/hook.js') || command.includes('.vibe-island/bin/vibe-island-bridge'));
}

function countManagedHookEntries(entries) {
  let count = 0;
  for (const entry of entries || []) {
    if (!entry || typeof entry !== 'object') continue;
    const hooks = Array.isArray(entry.hooks) ? entry.hooks : [];
    if (hooks.some((hook) => isManagedHookCommand(hook?.command || ''))) {
      count += 1;
    }
  }
  return count;
}

function countManagedCursorHookEntries(entries) {
  let count = 0;
  for (const entry of entries || []) {
    const command = entry && typeof entry === 'object' ? entry.command || '' : '';
    if (isManagedHookCommand(command)) {
      count += 1;
    }
  }
  return count;
}

function logHookSummary(label, eventNames, entriesByEvent, counter) {
  const parts = eventNames.map((eventName) => `${eventName}:${counter(entriesByEvent[eventName] || [])}`);
  console.log(`${label} managed hooks -> ${parts.join(', ')}`);
}

function installClaudeHooks() {
  installClaudeFamilyHooks(claudeSettingsPath, claudeCommand);
}

function installQoderHooks() {
  installClaudeFamilyHooks(qoderSettingsPath, qoderCommand);
}

function installCursorHooks() {
  const config = readJson(cursorHooksPath, {});
  const hooks = config.hooks && typeof config.hooks === 'object' && !Array.isArray(config.hooks)
    ? config.hooks
    : config;

  for (const eventName of Object.keys(hooks)) {
    const entries = Array.isArray(hooks[eventName]) ? hooks[eventName] : [];
    hooks[eventName] = entries.filter((entry) => {
      const hookCommand = entry && typeof entry === 'object' ? entry.command || '' : '';
      return !hookCommand.includes('bridge/hook.js') && !hookCommand.includes('.vibe-island/bin/vibe-island-bridge');
    });

    if (!hooks[eventName].length) {
      delete hooks[eventName];
    }
  }

  for (const eventName of cursorEvents) {
    hooks[eventName] = hooks[eventName] || [];
    hooks[eventName].push({ command: cursorCommand });
  }

  if (config.hooks && typeof config.hooks === 'object' && !Array.isArray(config.hooks)) {
    config.hooks = hooks;
  } else {
    Object.assign(config, hooks);
  }

  backupFile(cursorHooksPath);
  writeJson(cursorHooksPath, config);
  logHookSummary('Cursor', cursorEvents, hooks, countManagedCursorHookEntries);
}

function installGeminiHooks() {
  const settings = readJson(geminiSettingsPath, {});
  settings.hooks = settings.hooks || {};

  for (const [eventName, entries] of Object.entries(settings.hooks)) {
    settings.hooks[eventName] = filterManagedEntries(entries, geminiCommand);
  }

  for (const eventName of geminiEvents) {
    settings.hooks[eventName] = settings.hooks[eventName] || [];
    settings.hooks[eventName].unshift(managedCommandEntry(geminiCommand));
  }

  backupFile(geminiSettingsPath);
  writeJson(geminiSettingsPath, settings);
  logHookSummary('Gemini', geminiEvents, settings.hooks, countManagedHookEntries);
}

function installClaudeFamilyHooks(settingsPath, command) {
  const settings = readJson(settingsPath, {});
  settings.hooks = settings.hooks || {};

  if (Object.prototype.hasOwnProperty.call(settings.hooks, 'beforeStart')) {
    delete settings.hooks.beforeStart;
  }

  for (const [eventName, entries] of Object.entries(settings.hooks)) {
    settings.hooks[eventName] = filterManagedEntries(entries, command);
  }

  for (const eventName of matcherEvents) {
    settings.hooks[eventName] = settings.hooks[eventName] || [];
    settings.hooks[eventName].unshift(managedCommandEntry(command, '*'));
    settings.hooks[eventName] = dedupeHookEntries(settings.hooks[eventName]);
  }

  for (const eventName of passiveEvents) {
    settings.hooks[eventName] = settings.hooks[eventName] || [];
    settings.hooks[eventName].unshift(managedCommandEntry(command));
    settings.hooks[eventName] = dedupeHookEntries(settings.hooks[eventName]);
  }

  backupFile(settingsPath);
  writeJson(settingsPath, settings);
  const label = settingsPath === claudeSettingsPath ? 'Claude' : 'Qoder';
  logHookSummary(label, [...matcherEvents, ...passiveEvents], settings.hooks, countManagedHookEntries);
}

function ensureCodexHooksFeature() {
  ensureDir(codexConfigPath);
  const content = fs.existsSync(codexConfigPath) ? fs.readFileSync(codexConfigPath, 'utf8') : '';
  if (content.includes('[features]') && content.includes('hooks = true') && !content.includes('codex_hooks = true')) return;

  let nextContent = content.trimEnd();
  if (!nextContent.includes('[features]')) {
    nextContent += '\n\n[features]\n';
  } else if (!nextContent.endsWith('\n')) {
    nextContent += '\n';
  }

  if (nextContent.includes('codex_hooks = true')) {
    nextContent = nextContent.replace(/(^|\n)codex_hooks = true(?=\n|$)/g, '$1hooks = true');
  }

  if (!nextContent.includes('hooks = true')) {
    nextContent += 'hooks = true\n';
  }

  backupFile(codexConfigPath);
  fs.writeFileSync(codexConfigPath, `${nextContent.endsWith('\n') ? nextContent : `${nextContent}\n`}`);
}

function installCodexHooks() {
  const config = readJson(codexHooksPath, { hooks: {} });
  config.hooks = config.hooks || {};

  for (const [eventName, entries] of Object.entries(config.hooks)) {
    const filteredEntries = filterManagedEntries(entries, codexCommand);
    if (filteredEntries.length > 0) {
      config.hooks[eventName] = filteredEntries;
    } else {
      delete config.hooks[eventName];
    }
  }

  for (const eventName of codexEvents) {
    config.hooks[eventName] = config.hooks[eventName] || [];
    const needsMatcher = codexMatcherEvents.includes(eventName);
    config.hooks[eventName].unshift(managedCommandEntry(codexCommand, needsMatcher ? '*' : undefined));
    config.hooks[eventName] = dedupeHookEntries(config.hooks[eventName]);
  }

  backupFile(codexHooksPath);
  writeJson(codexHooksPath, config);
  logHookSummary('Codex', codexEvents, config.hooks, countManagedHookEntries);
}

function main() {
  installClaudeHooks();
  console.log('Installed NotchMonitor hooks for Claude');

  installCursorHooks();
  console.log('Installed NotchMonitor hooks for Cursor');

  installGeminiHooks();
  console.log('Installed NotchMonitor hooks for Gemini');

  installQoderHooks();
  console.log('Installed NotchMonitor hooks for Qoder');

  ensureCodexHooksFeature();
  installCodexHooks();
  console.log('Installed NotchMonitor hooks for Codex');
}

main();
