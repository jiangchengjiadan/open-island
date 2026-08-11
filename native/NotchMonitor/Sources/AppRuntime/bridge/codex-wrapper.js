const net = require('net');
const path = require('path');
const fs = require('fs');
const { spawn } = require('child_process');
const {
  slug,
  terminalOf,
  ttyOf,
  processInfoOf,
  processChainOf,
  collectEnvHints,
  collectJetBrainsContext,
  isJetBrainsTerminal,
  terminalTitleTokenFor,
  writeTerminalTitle
} = require('./utils');

const SOCKET_PATH = process.env.NOTCH_MONITOR_SOCKET_PATH || `/tmp/open-island-${process.getuid()}.sock`;
const LOG_PATH = '/tmp/notch-monitor-codex-wrapper.log';

function log(message) {
  if (process.env.NOTCH_MONITOR_DEBUG !== '1') return;
  try {
    fs.appendFileSync(LOG_PATH, `[${new Date().toISOString()}] ${message}\n`);
  } catch (_) {}
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
        this.send({ type: 'hello', data: { version: 1, role: 'wrapper' } });
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

  if (process.env.NOTCH_MONITOR_SET_TERMINAL_TITLE === '1' && terminalTitleToken) {
    const wroteTitle = writeTerminalTitle(`${cwdName} · ${terminalTitleToken}`);
    log(`terminal title token=${terminalTitleToken} wrote=${wroteTitle}`);
  }

  log(`launch wrapper pid=${process.pid} argsCount=${codexArgs.length}`);

  const child = spawn(realBinary, codexArgs, {
    stdio: 'inherit',
    cwd: process.cwd(),
    env: process.env,
  });
  agent.pid = child.pid ?? process.pid;
  agent.terminalTitleToken = isJetBrainsTerminal() ? terminalTitleTokenFor('codex', agent.pid) : agent.terminalTitleToken;

  if (process.env.NOTCH_MONITOR_SET_TERMINAL_TITLE === '1' && agent.terminalTitleToken) {
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

  // The child shares the foreground process group and receives terminal signals directly.
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
