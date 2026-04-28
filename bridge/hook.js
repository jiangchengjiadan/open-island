const fs = require('fs');
const net = require('net');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

const SOCKET_PATH = '/tmp/notch-monitor.sock';
const HOOK_LOG_PATH = '/tmp/notch-monitor-hook.log';

function log(message) {
  fs.appendFileSync(HOOK_LOG_PATH, `[${new Date().toISOString()}] ${message}\n`);
}

function readStdin() {
  return new Promise((resolve) => {
    if (process.stdin.isTTY) {
      resolve('');
      return;
    }

    let data = '';
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', (chunk) => {
      data += chunk;
    });
    process.stdin.on('end', () => resolve(data));
    process.stdin.resume();
  });
}

function parseJson(text) {
  if (!text || !text.trim()) return {};
  try {
    return JSON.parse(text);
  } catch (error) {
    fs.appendFileSync(HOOK_LOG_PATH, `[${new Date().toISOString()}] JSON parse failed: ${error.message}\n${text}\n\n`);
    return {};
  }
}

function slug(text, fallback = 'session') {
  return String(text || fallback)
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9._-]+/g, '-')
    .replace(/^-+|-+$/g, '') || fallback;
}

function eventNameOf(payload) {
  return (
    payload.hookEventName ||
    payload.hook_event_name ||
    payload.eventName ||
    payload.event_name ||
    payload.event ||
    payload.trigger ||
    'unknown'
  );
}

function matcherOf(payload) {
  return (
    payload.matcher ||
    payload.tool_name ||
    payload.toolName ||
    payload.tool ||
    payload.tool?.name ||
    payload.data?.tool_name ||
    payload.data?.toolName ||
    payload.permission?.tool_name ||
    payload.permission?.toolName ||
    ''
  );
}

function sessionIdOf(source, payload) {
  return (
    payload.session_id ||
    payload.sessionId ||
    payload.parent_session_id ||
    payload.parentSessionId ||
    process.env.CLAUDE_SESSION_ID ||
    process.env.CLAUDE_SESSION_NAME ||
    process.env.CODEX_SESSION_ID ||
    `${source}:${slug(payload.cwd || process.cwd())}`
  );
}

function sessionNameOf(source, payload) {
  return (
    payload.session_name ||
    payload.sessionName ||
    process.env.CLAUDE_SESSION_NAME ||
    payload.cwd && path.basename(payload.cwd) ||
    `${source}-session`
  );
}

function terminalOf() {
  const inferredApp = inferredTerminalApp(processChainOf(process.ppid));
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

function ttyOf() {
  try {
    const tty = execFileSync('/usr/bin/tty', [], { encoding: 'utf8', stdio: ['inherit', 'pipe', 'ignore'] }).trim();
    if (!tty || tty === 'not a tty') {
      const parentTTY = parentTTYOf();
      return parentTTY || terminalOf();
    }
    return tty.replace('/dev/', '');
  } catch (_) {
    return parentTTYOf() || terminalOf();
  }
}

function parentTTYOf() {
  try {
    const tty = execFileSync('/bin/ps', ['-p', String(process.ppid), '-o', 'tty='], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
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

function normalizedTTY() {
  return ttyOf().replace(/^\/dev\//, '');
}

function ttyDevicePath() {
  const tty = normalizedTTY();
  if (!tty.startsWith('ttys') && !tty.startsWith('pts/')) {
    return null;
  }
  return `/dev/${tty}`;
}

function terminalTitleTokenFor(source, pid, sessionId) {
  const sessionPart = slug(sessionId || 'session').slice(0, 12);
  return `OI ${source} ${normalizedTTY()} p${pid} ${sessionPart}`;
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

function currentTaskFromPayload(eventName, payload) {
  const prompt =
    payload.prompt ||
    payload.user_prompt ||
    payload.userPrompt ||
    payload.message ||
    payload.transcript_message;

  const toolName = matcherOf(payload);
  const toolInput = payload.tool_input || payload.toolInput || payload.input || {};
  const filePath = toolInput.file_path || toolInput.filePath || toolInput.path;
  const command = toolInput.command || toolInput.cmd;

  switch (eventName) {
    case 'UserPromptSubmit':
      return prompt || 'User prompt submitted';
    case 'PreToolUse':
      return [toolName, filePath || command].filter(Boolean).join(' ');
    case 'PostToolUse':
      return [toolName, filePath || command].filter(Boolean).join(' ');
    case 'Notification':
      return prompt || payload.title || 'Agent notification';
    case 'SessionStart':
      return prompt || 'Session started';
    case 'Stop':
      return prompt || 'Waiting for user input';
    case 'SessionEnd':
      return 'Session ended';
    default:
      return prompt || toolName || 'Working';
  }
}

function statusFromEvent(eventName, payload) {
  if (eventName === 'Stop') return 'waiting';
  if (eventName === 'SessionEnd') return 'completed';
  if (payload.level === 'error' || payload.error) return 'error';
  return 'running';
}

function toolNeedsApproval(toolName) {
  const normalized = normalizePermissionPart(toolName).toLowerCase();
  const mutableTools = new Set([
    'bash',
    'edit',
    'write',
    'multiedit',
    'notebookedit',
    'task',
    'shell',
    'runshellcommand',
    'run_shell_command',
  ]);
  return mutableTools.has(normalized);
}

function permissionMessage(toolName, payload) {
  const toolInput = toolInputOf(payload);
  const filePath = permissionFilePath(payload, false);
  const command = permissionCommand(payload);
  const target = filePath || command || JSON.stringify(toolInput);
  return `${toolName}${target ? ` ${target}` : ''}`;
}

function toolInputOf(payload) {
  return (
    payload.tool_input ||
    payload.toolInput ||
    payload.input ||
    payload.data?.tool_input ||
    payload.data?.toolInput ||
    payload.permission?.tool_input ||
    payload.permission?.toolInput ||
    payload.tool?.input ||
    {}
  );
}

function permissionFilePath(payload, resolvePath = true) {
  const toolInput = toolInputOf(payload);
  const filePath = toolInput.file_path || toolInput.filePath || toolInput.path;
  if (!filePath || !resolvePath) return filePath || null;
  if (path.isAbsolute(filePath)) return filePath;
  return path.resolve(payload.cwd || process.cwd(), filePath);
}

function permissionCommand(payload) {
  const toolInput = toolInputOf(payload);
  return toolInput.command || toolInput.cmd || null;
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

function permissionKey(toolName, payload) {
  const type = normalizePermissionPart(toolName);
  if (!type) return '';

  if (['Edit', 'Write', 'MultiEdit', 'NotebookEdit'].includes(type)) {
    return `${type}:file:${normalizePermissionPart(permissionFilePath(payload))}`;
  }

  if (type === 'Bash') {
    return `${type}:command:${normalizePermissionPart(permissionCommand(payload))}`;
  }

  return `${type}:input:${normalizePermissionPart(JSON.stringify(stablePermissionInput(toolInputOf(payload))))}`;
}

function permissionOutput(source, eventName, allowed) {
  if (source === 'codex') {
    return {
      continue: Boolean(allowed),
    };
  }

  const output = {
    continue: true,
    hookSpecificOutput: {
      hookEventName: eventName,
      permissionDecision: allowed ? 'allow' : 'deny',
      permissionDecisionReason: allowed
        ? 'Approved in NotchMonitor'
        : 'Denied in NotchMonitor',
    },
  };

  if (source !== 'codex') {
    output.suppressOutput = true;
  }

  return output;
}

class BridgeClient {
  constructor(agentId) {
    this.agentId = agentId;
    this.socket = null;
    this.connected = false;
    this.buffer = '';
    this.handlers = new Set();
  }

  connect() {
    return new Promise((resolve, reject) => {
      this.socket = net.createConnection(SOCKET_PATH, () => {
        this.connected = true;
        resolve();
      });

      this.socket.setEncoding('utf8');

      this.socket.on('data', (chunk) => {
        this.buffer += chunk;
        let newlineIndex = this.buffer.indexOf('\n');
        while (newlineIndex !== -1) {
          const rawMessage = this.buffer.slice(0, newlineIndex).trim();
          this.buffer = this.buffer.slice(newlineIndex + 1);
          if (rawMessage) {
            try {
              const message = JSON.parse(rawMessage);
              for (const handler of this.handlers) {
                handler(message);
              }
            } catch (_) {}
          }
          newlineIndex = this.buffer.indexOf('\n');
        }
      });

      this.socket.on('error', reject);
    });
  }

  send(message) {
    if (this.connected) {
      this.socket.write(`${JSON.stringify(message)}\n`);
    }
  }

  close() {
    if (this.socket) {
      this.socket.end();
    }
  }

  onMessage(handler) {
    this.handlers.add(handler);
    return () => this.handlers.delete(handler);
  }

  syncAgent(agent) {
    this.send({
      type: 'agent_update',
      data: agent,
    });
  }

  unregister() {
    this.send({
      type: 'agent_unregister',
      data: { id: this.agentId },
    });
  }

  requestPermission(request) {
    return new Promise((resolve) => {
      log(`permission requested agent=${this.agentId} request=${request.id} type=${request.type} message=${request.message}`);

      const stopListening = this.onMessage((message) => {
        const payload = Array.isArray(message.data) ? message.data[0] : message.data;
        if (
          message.type === 'permission_responded' &&
          payload &&
          payload.requestId === request.id
        ) {
          clearTimeout(timeout);
          stopListening();
          log(`permission responded agent=${this.agentId} request=${request.id} allowed=${Boolean(payload.allowed)}`);
          resolve(Boolean(payload.allowed));
        }
      });

      const timeout = setTimeout(() => {
        stopListening();
        log(`permission timed out agent=${this.agentId} request=${request.id} default=deny`);
        resolve(false);
      }, 600_000);

      this.send({
        type: 'permission_request',
        data: {
          agentId: this.agentId,
          request,
        },
      });
    });
  }
}

async function runEventHook(source) {
  const stdin = await readStdin();
  const payload = parseJson(stdin);
  const eventName = eventNameOf(payload);
  const sessionId = sessionIdOf(source, payload);
  const sessionName = sessionNameOf(source, payload);
  const agentId = `${source}:${sessionId}`;
  const parentInfo = processInfoOf(process.ppid);
  const terminalTitleToken = ttyDevicePath() ? terminalTitleTokenFor(source, process.ppid, sessionId) : null;
  const agent = {
    id: agentId,
    name: sessionName,
    type: source,
    status: statusFromEvent(eventName, payload),
    terminal: ttyOf(),
    terminalApp: terminalOf(),
    tty: ttyOf(),
    currentTask: currentTaskFromPayload(eventName, payload),
    cwd: payload.cwd || process.cwd(),
    pid: process.ppid,
    terminalTitleToken,
    parentPid: parentInfo?.ppid || null,
    parentCommand: parentInfo?.command || null,
    processChain: processChainOf(process.ppid),
    environmentHints: collectEnvHints(),
    jetbrainsContext: collectJetBrainsContext(),
    lastUpdate: Date.now(),
    needsPermission: false,
  };

  if ((eventName === 'SessionStart' || eventName === 'UserPromptSubmit') && terminalTitleToken) {
    const baseTitle = path.basename(agent.cwd || process.cwd()) || source;
    const wroteTitle = writeTerminalTitle(`${baseTitle} · ${terminalTitleToken}`);
    log(`terminal title token=${terminalTitleToken} wrote=${wroteTitle} source=${source} event=${eventName}`);
  }

  const client = new BridgeClient(agentId);
  try {
    await client.connect();
    client.syncAgent(agent);

    if (eventName === 'SessionEnd') {
      client.unregister();
      client.close();
      return;
    }

    if (eventName === 'PreToolUse' && toolNeedsApproval(matcherOf(payload))) {
      const toolName = matcherOf(payload);
      const requestId = `${agentId}:${Date.now()}`;
      const request = {
        id: requestId,
        type: toolName,
        message: permissionMessage(toolName, payload),
        filePath: permissionFilePath(payload),
        command: permissionCommand(payload),
        permissionKey: permissionKey(toolName, payload),
        timestamp: Date.now(),
      };

      const allowed = await client.requestPermission(request);
      process.stdout.write(`${JSON.stringify(permissionOutput(source, eventName, allowed))}\n`);
    } else if (source === 'qoder' && eventName === 'PreToolUse') {
      const toolName = matcherOf(payload);
      log(`qoder pretool observed without approval tool=${toolName || '<unknown>'} keys=${Object.keys(payload).sort().join(',')}`);
    }
  } catch (error) {
    fs.appendFileSync(HOOK_LOG_PATH, `[${new Date().toISOString()}] Hook error (${source}/${eventName}): ${error.message}\n`);
  } finally {
    client.close();
  }
}

async function runLegacyRegister(agentName, agentType = 'claude') {
  const agentId = `${agentType}:${slug(agentName)}:${Date.now()}`;
  const client = new BridgeClient(agentId);
  await client.connect();
  client.send({
    type: 'agent_register',
    data: {
      id: agentId,
      name: agentName,
      type: agentType,
      status: 'running',
      terminal: ttyOf(),
      terminalApp: terminalOf(),
      tty: ttyOf(),
      cwd: process.cwd(),
      pid: process.ppid,
      terminalTitleToken: ttyDevicePath() ? terminalTitleTokenFor(agentType, process.ppid, agentId) : null,
      parentPid: processInfoOf(process.ppid)?.ppid || null,
      parentCommand: processInfoOf(process.ppid)?.command || null,
      processChain: processChainOf(process.ppid),
      environmentHints: collectEnvHints(),
      jetbrainsContext: collectJetBrainsContext(),
      currentTask: 'Session started',
      lastUpdate: Date.now(),
    },
  });
  process.on('SIGINT', () => {
    client.unregister();
    client.close();
    process.exit(0);
  });
}

async function runLegacyUpdate(status, currentTask, agentType = 'claude') {
  const agentId = `${agentType}:${Date.now()}`;
  const client = new BridgeClient(agentId);
  await client.connect();
  client.send({
    type: 'agent_update',
    data: {
      id: agentId,
      name: `${agentType}-session`,
      type: agentType,
      status,
      terminal: ttyOf(),
      terminalApp: terminalOf(),
      tty: ttyOf(),
      cwd: process.cwd(),
      pid: process.ppid,
      terminalTitleToken: ttyDevicePath() ? terminalTitleTokenFor(agentType, process.ppid, agentId) : null,
      parentPid: processInfoOf(process.ppid)?.ppid || null,
      parentCommand: processInfoOf(process.ppid)?.command || null,
      processChain: processChainOf(process.ppid),
      environmentHints: collectEnvHints(),
      jetbrainsContext: collectJetBrainsContext(),
      currentTask,
      lastUpdate: Date.now(),
    },
  });
  client.close();
}

if (require.main === module) {
  const [command, ...rest] = process.argv.slice(2);

  Promise.resolve()
    .then(async () => {
      if (command === 'event') {
        await runEventHook(rest[0] || 'claude');
        return;
      }
      if (command === 'register') {
        await runLegacyRegister(rest[0] || 'claude-session', rest[1] || 'claude');
        return;
      }
      if (command === 'update') {
        await runLegacyUpdate(rest[0] || 'running', rest[1] || '', rest[2] || 'claude');
        return;
      }

      console.log('Usage: node hook.js [event <source>|register <name> <source>|update <status> <task> <source>]');
    })
    .catch((error) => {
      console.error('[NotchMonitor] Hook failed:', error.message);
      process.exit(1);
    });
}

module.exports = { runEventHook };
