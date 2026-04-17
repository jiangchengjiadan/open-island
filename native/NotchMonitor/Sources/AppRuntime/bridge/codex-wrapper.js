const net = require('net');
const os = require('os');
const path = require('path');
const fs = require('fs');
const { spawn, execFileSync } = require('child_process');

const SOCKET_PATH = '/tmp/notch-monitor.sock';
const LOG_PATH = '/tmp/notch-monitor-codex-wrapper.log';

function log(message) {
  try {
    fs.appendFileSync(LOG_PATH, `[${new Date().toISOString()}] ${message}\n`);
  } catch (_) {}
}

function slug(text, fallback = 'session') {
  return String(text || fallback)
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9._-]+/g, '-')
    .replace(/^-+|-+$/g, '') || fallback;
}

function terminalOf() {
  return (
    process.env.TERM_PROGRAM_APP ||
    process.env.TERM_PROGRAM ||
    process.env.TERM ||
    process.env.TTY ||
    os.hostname()
  );
}

function ttyOf() {
  try {
    const tty = execFileSync('/usr/bin/tty', [], { encoding: 'utf8', stdio: ['inherit', 'pipe', 'ignore'] }).trim();
    if (!tty || tty === 'not a tty') {
      return terminalOf();
    }
    return tty.replace('/dev/', '');
  } catch (_) {
    return terminalOf();
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
  ];

  return Object.fromEntries(
    keys
      .map((key) => [key, process.env[key]])
      .filter(([, value]) => typeof value === 'string' && value.trim() !== '')
  );
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

function normalizedTTY() {
  const tty = ttyOf();
  return tty.replace(/^\/dev\//, '');
}

function terminalTitleTokenFor(source, pid) {
  return `OI ${source} ${normalizedTTY()} p${pid}`;
}

function ttyDevicePath() {
  const tty = normalizedTTY();
  if (!tty.startsWith('ttys') && !tty.startsWith('pts/')) {
    return null;
  }
  return `/dev/${tty}`;
}

function writeTerminalTitle(title) {
  const ttyPath = ttyDevicePath();
  if (!ttyPath) return false;

  try {
    fs.writeFileSync(ttyPath, `\u001b]0;${title}\u0007`);
    return true;
  } catch (_) {
    return false;
  }
}

function currentTaskFromArgs(args) {
  const promptArgs = args.filter((arg) => typeof arg === 'string' && !arg.startsWith('-'));
  if (promptArgs.length > 0) {
    return promptArgs.join(' ').slice(0, 120);
  }
  return `Interactive session in ${path.basename(process.cwd()) || '~'}`;
}

class BridgeClient {
  constructor() {
    this.socket = null;
    this.connected = false;
  }

  connect() {
    return new Promise((resolve, reject) => {
      this.socket = net.createConnection(SOCKET_PATH, () => {
        this.connected = true;
        resolve();
      });

      this.socket.on('error', reject);
    });
  }

  send(message) {
    if (this.connected && this.socket?.writable) {
      this.socket.write(`${JSON.stringify(message)}\n`);
    }
  }

  close() {
    if (this.socket) {
      this.socket.end();
    }
  }
}

function parseArgs(argv) {
  const args = [...argv];
  let realBinary = process.env.NOTCH_MONITOR_REAL_CODEX || '';

  while (args.length > 0) {
    const token = args[0];
    if (token === '--real') {
      args.shift();
      realBinary = args.shift() || realBinary;
      continue;
    }
    break;
  }

  if (!realBinary) {
    throw new Error('Missing real Codex binary path');
  }

  return { realBinary, codexArgs: args };
}

async function main() {
  const { realBinary, codexArgs } = parseArgs(process.argv.slice(2));
  const cwdName = path.basename(process.cwd()) || '~';
  const agentId = `codex-wrapper:${process.pid}:${slug(process.cwd(), 'cwd')}`;
  const parentInfo = processInfoOf(process.pid);
  const terminalTitleToken = isJetBrainsTerminal() ? terminalTitleTokenFor('codex', process.pid) : null;
  const agent = {
    id: agentId,
    name: `codex — ${cwdName}`,
    type: 'codex',
    status: 'running',
    terminal: ttyOf(),
    terminalApp: terminalOf(),
    tty: ttyOf(),
    cwd: process.cwd(),
    pid: process.pid,
    terminalTitleToken,
    parentPid: parentInfo?.ppid || null,
    parentCommand: parentInfo?.command || null,
    processChain: processChainOf(process.pid),
    environmentHints: collectEnvHints(),
    jetbrainsContext: collectJetBrainsContext(),
    currentTask: currentTaskFromArgs(codexArgs),
    lastUpdate: Date.now(),
    needsPermission: false,
  };

  if (terminalTitleToken) {
    const wroteTitle = writeTerminalTitle(`${cwdName} · ${terminalTitleToken}`);
    log(`terminal title token=${terminalTitleToken} wrote=${wroteTitle}`);
  }

  log(`launch wrapper pid=${process.pid} cwd=${process.cwd()} real=${realBinary} args=${JSON.stringify(codexArgs)} envHints=${JSON.stringify(agent.environmentHints)} jetbrains=${JSON.stringify(agent.jetbrainsContext)} chain=${JSON.stringify(agent.processChain)}`);

  const child = spawn(realBinary, codexArgs, {
    stdio: 'inherit',
    cwd: process.cwd(),
    env: process.env,
  });
  agent.pid = child.pid ?? process.pid;
  agent.terminalTitleToken = isJetBrainsTerminal() ? terminalTitleTokenFor('codex', agent.pid) : agent.terminalTitleToken;

  if (agent.terminalTitleToken) {
    const wroteChildTitle = writeTerminalTitle(`${cwdName} · ${agent.terminalTitleToken}`);
    log(`terminal title updated token=${agent.terminalTitleToken} wrote=${wroteChildTitle}`);
  }

  log(`spawned child pid=${child.pid ?? 'unknown'}`);

  let bridge = null;
  let heartbeat = null;

  try {
    bridge = new BridgeClient();
    await bridge.connect();
    log(`connected to bridge socket ${SOCKET_PATH}`);
    bridge.send({ type: 'agent_register', data: agent });
    log(`registered agent ${agentId} (${agent.name})`);

    heartbeat = setInterval(() => {
      bridge.send({
        type: 'agent_update',
        data: {
          ...agent,
          lastUpdate: Date.now(),
        },
      });
      log(`heartbeat ${agentId}`);
    }, 15_000);
  } catch (error) {
    log(`bridge connect/register failed: ${error.message}`);
    // Monitoring is best-effort; Codex should still launch normally.
  }

  const shutdown = (signal) => {
    if (!child.killed) {
      child.kill(signal);
    }
  };

  process.on('SIGINT', () => shutdown('SIGINT'));
  process.on('SIGTERM', () => shutdown('SIGTERM'));

  child.on('exit', (code, signal) => {
    log(`child exit pid=${child.pid ?? 'unknown'} code=${code ?? 'null'} signal=${signal ?? 'null'}`);
    if (heartbeat) {
      clearInterval(heartbeat);
    }
    if (bridge) {
      bridge.send({ type: 'agent_unregister', data: { id: agentId } });
      log(`unregistered agent ${agentId}`);
      bridge.close();
    }

    if (signal) {
      process.kill(process.pid, signal);
      return;
    }
    process.exit(code ?? 0);
  });

  child.on('error', (error) => {
    log(`child error: ${error.message}`);
    if (heartbeat) {
      clearInterval(heartbeat);
    }
    if (bridge) {
      bridge.send({ type: 'agent_unregister', data: { id: agentId } });
      log(`unregistered agent after child error ${agentId}`);
      bridge.close();
    }
    console.error(`[NotchMonitor] Failed to launch Codex: ${error.message}`);
    process.exit(1);
  });
}

main().catch((error) => {
  log(`wrapper crash: ${error.message}`);
  console.error(`[NotchMonitor] Codex wrapper failed: ${error.message}`);
  process.exit(1);
});
