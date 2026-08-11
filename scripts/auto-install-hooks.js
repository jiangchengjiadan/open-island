#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { createHash } = require('crypto');

const repoRoot = path.resolve(__dirname, '..');
const nodePath = process.execPath;
const hookScript = path.join(repoRoot, 'bridge', 'hook.js');
const claudeSettingsPath = path.join(process.env.HOME, '.claude', 'settings.json');
const cursorHooksPath = path.join(process.env.HOME, '.cursor', 'hooks.json');
const geminiSettingsPath = path.join(process.env.HOME, '.gemini', 'settings.json');
const qoderSettingsPath = path.join(process.env.HOME, '.qoder', 'settings.json');
const codexConfigPath = path.join(process.env.HOME, '.codex', 'config.toml');
const codexHooksPath = path.join(process.env.HOME, '.codex', 'hooks.json');
const installCodexBridgeHooks = process.env.NOTCH_MONITOR_ENABLE_CODEX_HOOKS === '1';
const managedPrefix = 'OPEN_ISLAND_MANAGED=1';
const approvalPrefix = process.env.NOTCH_MONITOR_ENABLE_BLOCKING_APPROVALS === '1'
  ? ' NOTCH_MONITOR_ENABLE_BLOCKING_APPROVALS=1'
  : '';
const stateDirectory = path.join(process.env.XDG_STATE_HOME || path.join(process.env.HOME, '.local', 'state'), 'open-island');
const manifestPath = path.join(stateDirectory, 'hook-manifest.json');
const journalPath = path.join(stateDirectory, 'hook-journal.json');
const lockPath = path.join(stateDirectory, 'installer.lock');

function shellQuote(value) {
  return `'${String(value).replace(/'/g, `'"'"'`)}'`;
}

const claudeCommand = `${managedPrefix}${approvalPrefix} ${shellQuote(nodePath)} ${shellQuote(hookScript)} event claude`;
const cursorCommand = `${managedPrefix} ${shellQuote(nodePath)} ${shellQuote(hookScript)} event cursor`;
const geminiCommand = `${managedPrefix} ${shellQuote(nodePath)} ${shellQuote(hookScript)} event gemini`;
const qoderCommand = `${managedPrefix}${approvalPrefix} ${shellQuote(nodePath)} ${shellQuote(hookScript)} event qoder`;
const codexCommand = `${managedPrefix}${approvalPrefix} ${shellQuote(nodePath)} ${shellQuote(hookScript)} event codex`;

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
  atomicWriteFile(filePath, JSON.stringify(value, null, 2));
}

function atomicWriteFile(filePath, content) {
  ensureDir(filePath);
  let mode = 0o600;
  if (fs.existsSync(filePath)) {
    const stats = fs.lstatSync(filePath);
    if (!stats.isFile() || stats.isSymbolicLink()) {
      throw new Error(`Refusing to replace non-regular config file: ${filePath}`);
    }
    mode = stats.mode & 0o777;
  }
  const temporaryPath = `${filePath}.open-island.tmp.${process.pid}`;
  fs.writeFileSync(temporaryPath, content, { mode, flag: 'wx' });
  try {
    fs.renameSync(temporaryPath, filePath);
  } catch (error) {
    try { fs.unlinkSync(temporaryPath); } catch (_) {}
    throw error;
  }
}

function filterManagedEntries(entries, command) {
  const ownsCommand = (candidate) => command ? candidate === command : isManagedHookCommand(candidate);
  return (entries || []).filter((entry) => {
    if (typeof entry === 'string') {
      return !ownsCommand(entry);
    }

    if (!entry || !Array.isArray(entry.hooks)) return true;

    const nextHooks = entry.hooks.filter((hook) => {
      const hookCommand = hook.command || '';
      return !ownsCommand(hookCommand);
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
  return typeof command === 'string' && command.trimStart().startsWith(`${managedPrefix} `);
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
      return hookCommand !== cursorCommand;
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
  atomicWriteFile(codexConfigPath, `${nextContent.endsWith('\n') ? nextContent : `${nextContent}\n`}`);
}

function installCodexHooks(enabled = installCodexBridgeHooks) {
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

  if (!enabled) {
    backupFile(codexHooksPath);
    writeJson(codexHooksPath, config);
    logHookSummary('Codex', codexEvents, config.hooks, countManagedHookEntries);
    return;
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

function selectedTools(argv) {
  const toolsIndex = argv.indexOf('--tools');
  if (toolsIndex === -1 || !argv[toolsIndex + 1]) return [];
  return argv[toolsIndex + 1].split(',').map((value) => value.trim()).filter(Boolean);
}

const supportedTools = new Set(['claude', 'cursor', 'gemini', 'qoder', 'codex']);

function validateTools(tools) {
  for (const tool of tools) {
    if (!supportedTools.has(tool)) throw new Error(`Unknown tool: ${tool}`);
  }
}

function targetPathsForTools(tools) {
  const paths = [];
  for (const tool of tools) {
    if (tool === 'claude') paths.push(claudeSettingsPath);
    if (tool === 'cursor') paths.push(cursorHooksPath);
    if (tool === 'gemini') paths.push(geminiSettingsPath);
    if (tool === 'qoder') paths.push(qoderSettingsPath);
    if (tool === 'codex') paths.push(codexConfigPath, codexHooksPath);
  }
  return Array.from(new Set(paths));
}

function buildPlan(tools) {
  const targets = {
    claude: claudeSettingsPath,
    cursor: cursorHooksPath,
    gemini: geminiSettingsPath,
    qoder: qoderSettingsPath,
    codex: codexHooksPath,
  };
  const value = {
    mode: 'plan',
    tools,
    changes: tools.map((tool) => ({ tool, target: targets[tool], beforeHash: fileHash(targets[tool]), action: 'install-managed-hooks' })),
  };
  value.digest = createHash('sha256').update(JSON.stringify(value)).digest('hex');
  return value;
}

function plan(tools, planFile) {
  const value = buildPlan(tools);
  if (planFile) atomicWriteFile(planFile, `${JSON.stringify(value, null, 2)}\n`);
  console.log(JSON.stringify(value, null, 2));
}

function fileHash(filePath) {
  if (!filePath || !fs.existsSync(filePath)) return null;
  return createHash('sha256').update(fs.readFileSync(filePath)).digest('hex');
}

function writeManifest(tools, ownership = {}) {
  ensurePrivateStateDirectory();
  atomicWriteFile(manifestPath, `${JSON.stringify({
    version: 2,
    tools,
    managedPrefix,
    ownership,
    updatedAt: new Date().toISOString(),
  }, null, 2)}\n`);
}

function ensurePrivateStateDirectory() {
  fs.mkdirSync(stateDirectory, { recursive: true, mode: 0o700 });
  fs.chmodSync(stateDirectory, 0o700);
}

function acquireInstallerLock() {
  ensurePrivateStateDirectory();
  if (fs.existsSync(lockPath)) {
    const existing = readJson(lockPath, null);
    let live = false;
    if (Number.isInteger(existing?.pid) && existing.pid > 0) {
      try { process.kill(existing.pid, 0); live = true; } catch (error) { live = error.code !== 'ESRCH'; }
    }
    if (live) throw new Error(`Another Open Island installer is running with pid ${existing.pid}`);
    fs.unlinkSync(lockPath);
  }
  fs.writeFileSync(lockPath, JSON.stringify({ pid: process.pid }), { mode: 0o600, flag: 'wx' });
}

function releaseInstallerLock() {
  const owner = readJson(lockPath, null);
  if (owner?.pid === process.pid && fs.existsSync(lockPath)) fs.unlinkSync(lockPath);
}

function createSnapshots(filePaths) {
  return filePaths.map((filePath) => {
    const existed = fs.existsSync(filePath);
    const baseHash = fileHash(filePath);
    return {
      filePath,
      existed,
      data: existed ? fs.readFileSync(filePath).toString('base64') : null,
      baseHash,
      appliedHash: baseHash,
    };
  });
}

function writeTransactionJournal(snapshots) {
  atomicWriteFile(journalPath, `${JSON.stringify({ version: 2, state: 'prepared', snapshots }, null, 2)}\n`);
}

function recordAppliedState(snapshots) {
  for (const snapshot of snapshots) snapshot.appliedHash = fileHash(snapshot.filePath);
  writeTransactionJournal(snapshots);
}

function restoreSnapshots(snapshots, requireAppliedMatch = false) {
  if (requireAppliedMatch) {
    const conflicts = (snapshots || []).filter((snapshot) => fileHash(snapshot.filePath) !== snapshot.appliedHash);
    if (conflicts.length) {
      throw new Error(`Recovery conflict; files changed after the interrupted install and were preserved: ${conflicts.map((item) => item.filePath).join(', ')}`);
    }
  }
  for (const snapshot of snapshots || []) {
    if (snapshot.existed) atomicWriteFile(snapshot.filePath, Buffer.from(snapshot.data, 'base64'));
    else if (fs.existsSync(snapshot.filePath)) fs.unlinkSync(snapshot.filePath);
  }
}

function recoverInterruptedTransaction() {
  if (!fs.existsSync(journalPath)) return;
  const journal = readJson(journalPath, null);
  if (!journal || journal.version !== 2 || !Array.isArray(journal.snapshots)) {
    throw new Error(`Invalid installer journal: ${journalPath}`);
  }
  restoreSnapshots(journal.snapshots, true);
  fs.unlinkSync(journalPath);
}

function status() {
  const manifest = readJson(manifestPath, { version: 2, tools: [], ownership: {} });
  console.log(JSON.stringify({ mode: 'status', manifestPath, ...manifest }, null, 2));
}

function uninstallClaudeFamily(settingsPath, label, command) {
  const settings = readJson(settingsPath, {});
  if (!settings.hooks || typeof settings.hooks !== 'object') return;
  for (const [eventName, entries] of Object.entries(settings.hooks)) {
    const filtered = filterManagedEntries(entries, command);
    if (filtered.length) settings.hooks[eventName] = filtered;
    else delete settings.hooks[eventName];
  }
  backupFile(settingsPath);
  writeJson(settingsPath, settings);
  console.log(`Removed Open Island hooks for ${label}`);
}

function uninstallCursor(command) {
  const config = readJson(cursorHooksPath, {});
  const hooks = config.hooks && typeof config.hooks === 'object' && !Array.isArray(config.hooks) ? config.hooks : config;
  for (const eventName of Object.keys(hooks)) {
    if (!Array.isArray(hooks[eventName])) continue;
    hooks[eventName] = hooks[eventName].filter((entry) => entry?.command !== command);
    if (!hooks[eventName].length) delete hooks[eventName];
  }
  backupFile(cursorHooksPath);
  writeJson(cursorHooksPath, config);
  console.log('Removed Open Island hooks for Cursor');
}

function generatedCommandForTool(tool) {
  return { claude: claudeCommand, cursor: cursorCommand, gemini: geminiCommand, qoder: qoderCommand, codex: codexCommand }[tool];
}

function managedCommandsInEntries(entries) {
  const commands = [];
  for (const entry of entries || []) {
    if (typeof entry === 'string' && isManagedHookCommand(entry)) commands.push(entry);
    if (isManagedHookCommand(entry?.command || '')) commands.push(entry.command);
    for (const hook of entry?.hooks || []) {
      if (isManagedHookCommand(hook?.command || '')) commands.push(hook.command);
    }
  }
  return commands;
}

function managedCommandsForTool(tool) {
  const target = tool === 'claude' ? claudeSettingsPath
    : tool === 'cursor' ? cursorHooksPath
      : tool === 'gemini' ? geminiSettingsPath
        : tool === 'qoder' ? qoderSettingsPath
          : codexHooksPath;
  const config = readJson(target, {});
  const hooks = tool === 'cursor'
    ? (config.hooks && typeof config.hooks === 'object' && !Array.isArray(config.hooks) ? config.hooks : config)
    : (config.hooks || {});
  return Array.from(new Set(Object.values(hooks).flatMap(managedCommandsInEntries)));
}

function removeOwnedCommandForTool(tool, command) {
  if (!command) return;
  if (tool === 'claude') uninstallClaudeFamily(claudeSettingsPath, 'Claude', command);
  else if (tool === 'cursor') uninstallCursor(command);
  else if (tool === 'gemini') uninstallClaudeFamily(geminiSettingsPath, 'Gemini', command);
  else if (tool === 'qoder') uninstallClaudeFamily(qoderSettingsPath, 'Qoder', command);
  else if (tool === 'codex') uninstallClaudeFamily(codexHooksPath, 'Codex', command);
}

function uninstall(tools) {
  let snapshots = [];
  let transactionPrepared = false;
  acquireInstallerLock();
  try {
    recoverInterruptedTransaction();
    const manifest = readJson(manifestPath, { version: 2, tools: [], ownership: {} });
    const ownedCommands = {};
    for (const tool of tools) {
      const command = manifest.ownership?.[tool]?.command;
      const presentCommands = managedCommandsForTool(tool);
      if (!command && presentCommands.length) {
        throw new Error(`Ownership conflict for ${tool}; manifest has no installed command fingerprint`);
      }
      const divergent = presentCommands.filter((candidate) => candidate !== command);
      if (divergent.length) {
        throw new Error(`Ownership conflict for ${tool}; managed command was modified and was preserved`);
      }
      ownedCommands[tool] = command;
    }
    snapshots = createSnapshots([...targetPathsForTools(tools), manifestPath]);
    writeTransactionJournal(snapshots);
    transactionPrepared = true;
    for (const tool of tools) {
      removeOwnedCommandForTool(tool, ownedCommands[tool]);
      recordAppliedState(snapshots);
    }
    const nextOwnership = { ...(manifest.ownership || {}) };
    for (const tool of tools) delete nextOwnership[tool];
    writeManifest((manifest.tools || []).filter((tool) => !tools.includes(tool)), nextOwnership);
    recordAppliedState(snapshots);
    fs.unlinkSync(journalPath);
  } catch (error) {
    if (transactionPrepared) {
      try {
        restoreSnapshots(snapshots, true);
        if (fs.existsSync(journalPath)) fs.unlinkSync(journalPath);
      } catch (rollbackError) {
        throw new Error(`${error.message}; ${rollbackError.message}`);
      }
    }
    throw error;
  } finally {
    releaseInstallerLock();
  }
}

function apply(tools, expectedPlan) {
  if (!expectedPlan || !Array.isArray(expectedPlan.changes)) {
    throw new Error('Apply requires a plan file created by a prior plan command');
  }
  const digestSource = { mode: expectedPlan.mode, tools: expectedPlan.tools, changes: expectedPlan.changes };
  const digest = createHash('sha256').update(JSON.stringify(digestSource)).digest('hex');
  if (digest !== expectedPlan.digest) throw new Error('Plan digest mismatch');
  if (JSON.stringify(tools) !== JSON.stringify(expectedPlan.tools)) {
    throw new Error('Apply tool selection does not match the approved plan');
  }
  validateTools(tools);
  let snapshots = [];
  let transactionPrepared = false;
  acquireInstallerLock();
  try {
    recoverInterruptedTransaction();
    const manifest = readJson(manifestPath, { version: 2, tools: [], ownership: {} });
    const previousCommands = {};
    for (const tool of tools) {
      const previousCommand = manifest.ownership?.[tool]?.command;
      const presentCommands = managedCommandsForTool(tool);
      if (!previousCommand && presentCommands.length) {
        throw new Error(`Ownership conflict for ${tool}; manifest has no installed command fingerprint`);
      }
      if (previousCommand && presentCommands.some((candidate) => candidate !== previousCommand)) {
        throw new Error(`Ownership conflict for ${tool}; managed command was modified and was preserved`);
      }
      previousCommands[tool] = previousCommand;
    }
    for (const change of expectedPlan.changes) {
      if (fileHash(change.target) !== change.beforeHash) {
        throw new Error(`Configuration changed after plan; re-plan required: ${change.target}`);
      }
    }
    snapshots = createSnapshots([...targetPathsForTools(tools), manifestPath]);
    writeTransactionJournal(snapshots);
    transactionPrepared = true;
    for (const change of expectedPlan.changes) {
      if (fileHash(change.target) !== change.beforeHash) {
        throw new Error(`Configuration changed before commit; re-plan required: ${change.target}`);
      }
    }
    for (const tool of tools) {
      const nextCommand = generatedCommandForTool(tool);
      if (previousCommands[tool] && previousCommands[tool] !== nextCommand) {
        removeOwnedCommandForTool(tool, previousCommands[tool]);
        recordAppliedState(snapshots);
      }
      if (tool === 'claude') installClaudeHooks();
      else if (tool === 'cursor') installCursorHooks();
      else if (tool === 'gemini') installGeminiHooks();
      else if (tool === 'qoder') installQoderHooks();
      else if (tool === 'codex') {
        ensureCodexHooksFeature();
        installCodexHooks(true);
      }
      recordAppliedState(snapshots);
      if (process.env.OPEN_ISLAND_TEST_CRASH_AFTER_TOOL === tool) {
        process.kill(process.pid, 'SIGKILL');
      }
    }
    const ownership = { ...(manifest.ownership || {}) };
    for (const tool of tools) ownership[tool] = { command: generatedCommandForTool(tool) };
    writeManifest(Array.from(new Set([...(manifest.tools || []), ...tools])).sort(), ownership);
    recordAppliedState(snapshots);
    fs.unlinkSync(journalPath);
  } catch (error) {
    if (transactionPrepared) {
      try {
        restoreSnapshots(snapshots, true);
        if (fs.existsSync(journalPath)) fs.unlinkSync(journalPath);
      } catch (rollbackError) {
        throw new Error(`${error.message}; ${rollbackError.message}`);
      }
    }
    throw error;
  } finally {
    releaseInstallerLock();
  }
}

function main() {
  const argv = process.argv.slice(2);
  const planFileIndex = argv.indexOf('--plan-file');
  const planFile = planFileIndex >= 0 ? argv[planFileIndex + 1] : null;
  const expectedPlan = argv.includes('--apply') && planFile ? readJson(planFile, null) : null;
  const requestedTools = selectedTools(argv);
  const tools = argv.includes('--apply') ? (expectedPlan?.tools || []) : requestedTools;
  if (argv.includes('--apply') && requestedTools.length && JSON.stringify(requestedTools) !== JSON.stringify(tools)) {
    throw new Error('Apply tool selection does not match the approved plan');
  }
  if (!argv.includes('--apply') && !argv.includes('--uninstall')) {
    acquireInstallerLock();
    try {
      recoverInterruptedTransaction();
    } finally {
      releaseInstallerLock();
    }
  }
  if (argv.includes('--status')) {
    status();
    return;
  }
  if (tools.length === 0) {
    throw new Error('No tools selected. Use --tools claude,cursor,gemini,qoder,codex');
  }
  validateTools(tools);
  if (argv.includes('--apply')) apply(tools, expectedPlan);
  else if (argv.includes('--uninstall')) uninstall(tools);
  else plan(tools, planFile);
}

main();
