const fs = require('fs');
const net = require('net');
const path = require('path');
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

function parseJson(text) {
  if (!text || !text.trim()) return {};
  try {
    return JSON.parse(text);
  } catch (error) {
    fs.appendFileSync(HOOK_LOG_PATH, `[${new Date().toISOString()}] JSON parse failed: ${error.message}\n${text}\n\n`);
    return {};
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
  const mutableTools = new Set([
    'Bash',
    'Edit',
    'Write',
    'MultiEdit',
    'NotebookEdit',
    'Task',
  ]);
  return mutableTools.has(toolName);
}

function permissionMessage(toolName, payload) {
  const toolInput = payload.tool_input || payload.toolInput || payload.input || {};
  const filePath = toolInput.file_path || toolInput.filePath || toolInput.path;
  const command = toolInput.command || toolInput.cmd;
  const target = filePath || command || JSON.stringify(toolInput);
  return `${toolName}${target ? ` ${target}` : ''}`;
}

function permissionOutput(eventName, allowed) {
  return {
    continue: true,
    suppressOutput: true,
    hookSpecificOutput: {
      hookEventName: eventName,
      permissionDecision: allowed ? 'allow' : 'deny',
      permissionDecisionReason: allowed
        ? 'Approved in NotchMonitor'
        : 'Denied in NotchMonitor',
    },
  };
}

/**
 * 为 legacy register/update 生成稳定的 agent id，避免每次 update 都创建新会话。
 */
function legacyAgentId(agentType) {
  const tty = slug(ttyOf() || terminalOf(), 'terminal');
  const cwd = slug(process.cwd(), 'cwd');
  return `${agentType}:legacy:${tty}:${cwd}`;
}

/**
 * 解析 legacy 模式下展示用的 agent 名称，但不参与会话唯一标识。
 */
function legacyAgentName(agentType, agentName = '') {
  if (typeof agentName === 'string' && agentName.trim() !== '') {
    return agentName.trim();
  }
  if (typeof process.env.NOTCH_MONITOR_LEGACY_AGENT_NAME === 'string' && process.env.NOTCH_MONITOR_LEGACY_AGENT_NAME.trim() !== '') {
    return process.env.NOTCH_MONITOR_LEGACY_AGENT_NAME.trim();
  }
  return `${agentType}-session`;
}

/**
 * 构造 legacy 模式下共享的 agent payload，确保 register 和 update 命中同一标识。
 */
function legacyAgentPayload(agentId, agentName, agentType, status, currentTask) {
  return {
    id: agentId,
    name: agentName,
    type: agentType,
    status,
    terminal: ttyOf(),
    terminalApp: terminalOf(),
    tty: ttyOf(),
    cwd: process.cwd(),
    pid: process.ppid,
    terminalTitleToken: isJetBrainsTerminal() ? terminalTitleTokenFor(agentType, process.ppid, agentId) : null,
    parentPid: processInfoOf(process.ppid)?.ppid || null,
    parentCommand: processInfoOf(process.ppid)?.command || null,
    processChain: processChainOf(process.ppid),
    environmentHints: collectEnvHints(),
    jetbrainsContext: collectJetBrainsContext(),
    currentTask,
    lastUpdate: Date.now(),
  };
}

/**
 * 为 legacy register 注册清理钩子，避免遗留悬空会话。
 */
function registerLegacyCleanup(client) {
  let didCleanup = false;

  const cleanup = () => {
    if (didCleanup) {
      return;
    }
    didCleanup = true;
    client.unregister();
    client.close();
  };

  process.once('SIGINT', () => {
    cleanup();
    process.exit(0);
  });

  process.once('SIGTERM', () => {
    cleanup();
    process.exit(0);
  });

  process.once('exit', cleanup);
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
  const terminalTitleToken = isJetBrainsTerminal() ? terminalTitleTokenFor(source, process.ppid, sessionId) : null;
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
      const requestId = `${agentId}:${Date.now()}`;
      const request = {
        id: requestId,
        type: matcherOf(payload),
        message: permissionMessage(matcherOf(payload), payload),
        filePath:
          payload.tool_input?.file_path ||
          payload.toolInput?.filePath ||
          payload.input?.path ||
          null,
        timestamp: Date.now(),
      };

      const allowed = await client.requestPermission(request);
      process.stdout.write(`${JSON.stringify(permissionOutput(eventName, allowed))}\n`);
    }
  } catch (error) {
    fs.appendFileSync(HOOK_LOG_PATH, `[${new Date().toISOString()}] Hook error (${source}/${eventName}): ${error.message}\n`);
  } finally {
    client.close();
  }
}

async function runLegacyRegister(agentName, agentType = 'claude') {
  const resolvedName = legacyAgentName(agentType, agentName);
  const agentId = legacyAgentId(agentType);
  const client = new BridgeClient(agentId);
  await client.connect();
  client.send({
    type: 'agent_register',
    data: legacyAgentPayload(agentId, resolvedName, agentType, 'running', 'Session started'),
  });
  registerLegacyCleanup(client);
}

async function runLegacyUpdate(status, currentTask, agentType = 'claude') {
  // 保持 legacy update 与默认 legacy register 的名称一致，避免写入不同会话。
  const agentName = `${agentType}-session`;
  const agentId = legacyAgentId(agentType);
  const client = new BridgeClient(agentId);
  await client.connect();
  client.send({
    type: 'agent_update',
    data: legacyAgentPayload(agentId, agentName, agentType, status, currentTask),
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
