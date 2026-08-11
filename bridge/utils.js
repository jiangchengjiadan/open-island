const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

// Shared utility functions for Open Island bridge

function slug(text, fallback = 'session') {
  return String(text || fallback)
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9._-]+/g, '-')
    .replace(/^-+|-+$/g, '') || fallback;
}

function terminalOf(options = {}) {
  const processChainStartPid = options.processChainStartPid ?? process.pid;
  const inferredApp = inferredTerminalApp(processChainOf(processChainStartPid));
  if (inferredApp) {
    return inferredApp;
  }

  return (
    process.env.TERM_PROGRAM_APP ||
    process.env.TERM_PROGRAM ||
    process.env.TERM ||
    process.env.TTY ||
    os.hostname()
  );
}

function tmuxSocketPathFromEnv(env) {
  const raw = (env.TMUX || '').trim();
  if (!raw) return '';
  const separatorIndex = raw.indexOf(',');
  if (separatorIndex === -1) return raw;
  return raw.slice(0, separatorIndex);
}

function tmuxTargetOf(env) {
  const pane = (env.TMUX_PANE || '').trim();
  if (!pane) return '';

  try {
    const socketPath = tmuxSocketPathFromEnv(env);
    const args = socketPath
      ? ['-S', socketPath, 'display-message', '-p', '-t', pane, '#S:#I.#P']
      : ['display-message', '-p', '-t', pane, '#S:#I.#P'];
    const output = execFileSync('/usr/bin/env', ['tmux', ...args], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
      env,
    }).trim();
    return output;
  } catch (_) {
    return '';
  }
}

function inferredTerminalApp(processChain) {
  const termProgramApp = (process.env.TERM_PROGRAM_APP || '').trim();
  if (termProgramApp) return termProgramApp;

  const termProgram = (process.env.TERM_PROGRAM || '').trim();
  const joined = (processChain || []).join(' ').toLowerCase();

  if (process.env.VSCODE_GIT_IPC_HANDLE) {
    if (joined.includes('cursor')) return 'Cursor';
    return 'Visual Studio Code';
  }

  if (process.env.ITERM_SESSION_ID) {
    return 'iTerm';
  }

  if (termProgram && termProgram.toLowerCase() !== 'tmux') {
    return termProgram;
  }

  if (joined.includes('cursor')) return 'Cursor';
  if (joined.includes('visual studio code') || joined.includes('vscode') || joined.includes(':code ') || joined.endsWith(':code')) return 'Visual Studio Code';
  if (joined.includes('iterm')) return 'iTerm';
  if (joined.includes('warp')) return 'Warp';
  if (joined.includes('ghostty')) return 'Ghostty';
  if (joined.includes('terminal')) return 'Terminal';

  return '';
}

function ttyOf(options = {}) {
  const terminalOptions = options.terminalOptions || {};
  const parentPid = options.parentPid ?? process.ppid;
  const preferParentTTY = options.preferParentTTY === true;

  try {
    const tty = execFileSync('/usr/bin/tty', [], { encoding: 'utf8', stdio: ['inherit', 'pipe', 'ignore'] }).trim();
    if (!tty || tty === 'not a tty') {
      if (preferParentTTY) {
        const parentTTY = parentTTYOf(parentPid);
        return parentTTY || terminalOf(terminalOptions);
      }
      return terminalOf(terminalOptions);
    }
    return tty.replace('/dev/', '');
  } catch (_) {
    if (preferParentTTY) {
      const parentTTY = parentTTYOf(parentPid);
      return parentTTY || terminalOf(terminalOptions);
    }
    return terminalOf(terminalOptions);
  }
}

function parentTTYOf(pid = process.ppid) {
  try {
    const tty = execFileSync('/bin/ps', ['-p', String(pid), '-o', 'tty='], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
    if (!tty || tty === '??') {
      return '';
    }
    return tty;
  } catch (_) {
    return '';
  }
}

function processInfoOf(pid) {
  try {
    const output = execFileSync('/bin/ps', ['-p', String(pid), '-o', 'ppid=,comm='], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
    if (!output) return null;

    const columns = output.split(/\s+/, 2);
    if (columns.length < 2) return null;

    return {
      ppid: Number(columns[0]),
      command: path.basename(columns[1]),
    };
  } catch (_) {
    return null;
  }
}

function processChainOf(startPid, limit = 8) {
  const chain = [];
  let current = Number(startPid);
  const seen = new Set();

  while (current > 1 && chain.length < limit && !seen.has(current)) {
    seen.add(current);
    const info = processInfoOf(current);
    if (!info) break;
    chain.push(`${current}:${info.command}`);
    current = info.ppid;
  }

  return chain;
}

function collectEnvHints() {
  const keys = [
    'TERM',
    'TERM_PROGRAM',
    'TERM_PROGRAM_APP',
    'TERMINAL_EMULATOR',
    'COLORTERM',
    'SHELL',
    'PWD',
    'KITTY_WINDOW_ID',
    'ITERM_SESSION_ID',
    'ITERM_PROFILE',
    'VSCODE_GIT_IPC_HANDLE',
    'TMUX',
    'TMUX_PANE',
  ];

  const hints = Object.fromEntries(
    keys
      .map((key) => [key, process.env[key]])
      .filter(([, value]) => typeof value === 'string' && value.trim() !== '')
  );

  const tmuxTarget = tmuxTargetOf(process.env);
  if (tmuxTarget) {
    hints.TMUX_TARGET = tmuxTarget;
  }

  const tmuxSocketPath = tmuxSocketPathFromEnv(process.env);
  if (tmuxSocketPath) {
    hints.TMUX_SOCKET_PATH = tmuxSocketPath;
  }

  return hints;
}

function collectJetBrainsContext() {
  const prefixes = ['JETBRAINS', 'IDEA', 'PYCHARM'];
  const exactKeys = [
    'TERMINAL_EMULATOR',
    'TERM_PROGRAM',
    'TERM_PROGRAM_APP',
    'PWD',
    'SHELL',
  ];

  const entries = Object.entries(process.env).filter(([key, value]) => {
    if (typeof value !== 'string' || value.trim() === '') return false;
    return exactKeys.includes(key) || prefixes.some((prefix) => key.startsWith(prefix));
  });

  return Object.fromEntries(entries);
}

function isJetBrainsTerminal() {
  const marker = `${process.env.TERMINAL_EMULATOR || ''} ${process.env.TERM_PROGRAM || ''} ${process.env.TERM_PROGRAM_APP || ''}`.toLowerCase();
  return marker.includes('jediterm') || marker.includes('jetbrains') || marker.includes('idea') || marker.includes('pycharm');
}

function normalizedTTY(options = {}) {
  const tty = ttyOf(options);
  return tty.replace(/^\/dev\//, '');
}

function ttyDevicePath(options = {}) {
  const tty = normalizedTTY(options);
  if (!tty.startsWith('ttys') && !tty.startsWith('pts/')) {
    return null;
  }
  return `/dev/${tty}`;
}

function terminalTitleTokenFor(source, pid, sessionId = '', options = {}) {
  const sessionPart = slug(sessionId || 'session').slice(0, 12);
  return `OI ${source} ${normalizedTTY(options)} p${pid} ${sessionPart}`;
}

function writeTerminalTitle(title, options = {}) {
  const ttyPath = ttyDevicePath(options);
  if (!ttyPath) return false;

  try {
    require('fs').writeFileSync(ttyPath, `]0;${title}`);
    return true;
  } catch (_) {
    return false;
  }
}

function normalizePermissionPart(value) {
  if (value == null) return '';
  return String(value).trim().replace(/\s+/g, ' ');
}

function stablePermissionInput(value) {
  if (Array.isArray(value)) {
    return value.map(stablePermissionInput);
  }
  if (value && typeof value === 'object') {
    return Object.keys(value).sort().reduce((result, key) => {
      result[key] = stablePermissionInput(value[key]);
      return result;
    }, {});
  }
  return value;
}

module.exports = {
  slug,
  terminalOf,
  tmuxSocketPathFromEnv,
  tmuxTargetOf,
  inferredTerminalApp,
  ttyOf,
  parentTTYOf,
  processInfoOf,
  processChainOf,
  collectEnvHints,
  collectJetBrainsContext,
  isJetBrainsTerminal,
  normalizedTTY,
  ttyDevicePath,
  terminalTitleTokenFor,
  writeTerminalTitle,
  normalizePermissionPart,
  stablePermissionInput
};
