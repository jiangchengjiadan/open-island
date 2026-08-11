const fs = require('fs');
const net = require('net');
const path = require('path');
const { randomUUID } = require('crypto');
const { getIntegration } = require('./integrations');
const {
  slug,
  terminalOf,
  ttyOf,
  processInfoOf,
  processChainOf,
  collectEnvHints,
  collectJetBrainsContext,
  normalizedTTY,
  ttyDevicePath,
  terminalTitleTokenFor,
  writeTerminalTitle,
  normalizePermissionPart,
  stablePermissionInput,
} = require('./utils');

const SOCKET_PATH = process.env.NOTCH_MONITOR_SOCKET_PATH || `/tmp/open-island-${process.getuid()}.sock`;
const HOOK_LOG_PATH = '/tmp/notch-monitor-hook.log';

function log(message) {
  if (process.env.NOTCH_MONITOR_DEBUG !== '1') return;
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
    throw new Error(`Invalid hook JSON: ${error.message}`);
  }
}

function terminalResolutionOptions() {
  return { processChainStartPid: process.ppid };
}

function ttyResolutionOptions() {
  return {
    preferParentTTY: true,
    parentPid: process.ppid,
    terminalOptions: terminalResolutionOptions(),
  };
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
    payload.data?.tool?.name ||
    payload.permission?.matcher ||
    payload.permission?.tool_name ||
    payload.permission?.toolName ||
    payload.permission?.tool?.name ||
    ''
  );
}

function sessionIdOf(source, payload) {
  const ttyPart = slug(normalizedTTY(ttyResolutionOptions()) || terminalOf(terminalResolutionOptions()) || 'terminal');
  const fallback = `${source}:${slug(payload.cwd || process.cwd())}:${ttyPart}`;
  return getIntegration(source).sessionId(source, payload, process.env, fallback);
}

function sessionNameOf(source, payload) {
  const fallback = payload.cwd && path.basename(payload.cwd) || `${source}-session`;
  return getIntegration(source).sessionName(source, payload, process.env, fallback);
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
  const normalizedEvent = String(eventName || '').trim().toLowerCase();

  switch (eventName) {
    case 'UserPromptSubmit':
    case 'BeforeAgent':
      return prompt || 'User prompt submitted';
    case 'AfterAgent':
      return payload.prompt_response || payload.promptResponse || payload.message || 'Turn completed';
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
      break;
  }

  switch (normalizedEvent) {
    case 'beforesubmitprompt':
      return prompt || 'Prompt submitted';
    case 'beforeshellexecution':
      return command || payload.command || 'Shell execution';
    case 'beforemcpexecution':
      return [payload.server, payload.tool_name || payload.toolName || payload.tool?.name].filter(Boolean).join(' ') || 'MCP execution';
    case 'beforereadfile':
      return payload.file_path || payload.filePath || 'Read file';
    case 'afterfileedit':
      return payload.file_path || payload.filePath || 'File edited';
    case 'stop':
      return payload.message || payload.content || 'Turn completed';
    default:
      return prompt || toolName || payload.command || 'Working';
  }
}

function statusFromEvent(eventName, payload) {
  const normalizedEvent = String(eventName || '').trim().toLowerCase();
  if (eventName === 'Stop') return 'waiting';
  if (eventName === 'BeforeAgent') return 'running';
  if (eventName === 'AfterAgent') return 'completed';
  if (eventName === 'SessionEnd') return 'completed';
  if (eventName === 'Notification') return 'waiting';
  if (normalizedEvent === 'stop') {
    const rawStatus = String(payload.status || '').trim().toLowerCase();
    if (rawStatus.includes('error') || rawStatus.includes('failed')) return 'error';
    return 'completed';
  }
  if (normalizedEvent === 'notification') return 'waiting';
  if (
    normalizedEvent === 'beforesubmitprompt' ||
    normalizedEvent === 'beforeshellexecution' ||
    normalizedEvent === 'beforemcpexecution' ||
    normalizedEvent === 'beforereadfile'
  ) {
    return 'running';
  }
  if (normalizedEvent === 'afterfileedit') return 'completed';
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

function blockingApprovalsEnabled() {
  return process.env.NOTCH_MONITOR_ENABLE_BLOCKING_APPROVALS === '1';
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
    payload.data?.input ||
    payload.permission?.tool_input ||
    payload.permission?.toolInput ||
    payload.permission?.input ||
    payload.permission?.tool?.input ||
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
  return getIntegration(source).permissionOutput(eventName, allowed);
}

function legacyAgentId(agentType) {
  const explicitSessionID = process.env.NOTCH_MONITOR_LEGACY_SESSION_ID;
  if (typeof explicitSessionID === "string" && explicitSessionID.trim() !== "") {
    return explicitSessionID.trim();
  }

  const tty = slug(ttyOf(ttyResolutionOptions()) || terminalOf(terminalResolutionOptions()), "terminal");
  const cwd = slug(process.cwd(), "cwd");
  const parentPID = Number.isInteger(process.ppid) && process.ppid > 0 ? `p${process.ppid}` : "punknown";
  return `${agentType}:legacy:${tty}:${cwd}:${parentPID}`;
}

function legacyAgentName(agentType, agentName = "") {
  if (typeof agentName === "string" && agentName.trim() !== "") {
    return agentName.trim();
  }

  if (
    typeof process.env.NOTCH_MONITOR_LEGACY_AGENT_NAME === "string" &&
    process.env.NOTCH_MONITOR_LEGACY_AGENT_NAME.trim() !== ""
  ) {
    return process.env.NOTCH_MONITOR_LEGACY_AGENT_NAME.trim();
  }

  return `${agentType}-session`;
}

function legacyAgentPayload(agentId, agentName, agentType, status, currentTask) {
  return {
    id: agentId,
    name: agentName,
    type: agentType,
    status,
    terminal: ttyOf(ttyResolutionOptions()),
    terminalApp: terminalOf(terminalResolutionOptions()),
    tty: ttyOf(ttyResolutionOptions()),
    cwd: process.cwd(),
    pid: process.ppid,
    terminalTitleToken: ttyDevicePath(ttyResolutionOptions()) ? terminalTitleTokenFor(agentType, process.ppid, agentId, ttyResolutionOptions()) : null,
    parentPid: processInfoOf(process.ppid)?.ppid || null,
    parentCommand: processInfoOf(process.ppid)?.command || null,
    processChain: processChainOf(process.ppid),
    environmentHints: collectEnvHints(),
    jetbrainsContext: collectJetBrainsContext(),
    currentTask,
    lastUpdate: Date.now(),
  };
}

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

  process.once("SIGINT", () => {
    cleanup();
    process.exit(0);
  });

  process.once("SIGTERM", () => {
    cleanup();
    process.exit(0);
  });

  process.once("exit", cleanup);
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
        this.send({ type: 'hello', data: { version: 1, role: 'hook' } });
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
      log(`permission requested agent=${this.agentId} request=${request.id} type=${request.type}`);

      const stopListening = this.onMessage((message) => {
        const payload = Array.isArray(message.data) ? message.data[0] : message.data;
        if (
          message.type === 'permission_responded' &&
          payload &&
          payload.requestId === request.id
        ) {
          clearTimeout(timeout);
          this.socket?.off('close', handleDisconnect);
          stopListening();
          log(`permission responded agent=${this.agentId} request=${request.id} allowed=${Boolean(payload.allowed)}`);
          resolve(Boolean(payload.allowed));
        }
      });

      const handleDisconnect = () => {
        clearTimeout(timeout);
        stopListening();
        resolve(false);
      };
      this.socket?.once('close', handleDisconnect);

      const timeout = setTimeout(() => {
        stopListening();
        this.socket?.off('close', handleDisconnect);
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
  const terminalTitleToken = ttyDevicePath(ttyResolutionOptions()) ? terminalTitleTokenFor(source, process.ppid, sessionId, ttyResolutionOptions()) : null;
  const resolvedCwd = typeof getIntegration(source).resolvedCwd === 'function'
    ? getIntegration(source).resolvedCwd(payload, process.cwd())
    : (payload.cwd || process.cwd());
  const agent = {
    id: agentId,
    name: sessionName,
    type: source,
    status: statusFromEvent(eventName, payload),
    terminal: ttyOf(ttyResolutionOptions()),
    terminalApp: terminalOf(terminalResolutionOptions()),
    tty: ttyOf(ttyResolutionOptions()),
    currentTask: currentTaskFromPayload(eventName, payload),
    cwd: resolvedCwd,
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

  if (process.env.NOTCH_MONITOR_SET_TERMINAL_TITLE === '1' && (eventName === 'SessionStart' || eventName === 'UserPromptSubmit') && terminalTitleToken) {
    const baseTitle = path.basename(agent.cwd || process.cwd()) || source;
    const wroteTitle = writeTerminalTitle(`${baseTitle} · ${terminalTitleToken}`, ttyResolutionOptions());
    log(`terminal title token=${terminalTitleToken} wrote=${wroteTitle} source=${source} event=${eventName}`);
  }

  const client = new BridgeClient(agentId);
  try {
    await client.connect();
    client.syncAgent(agent);

    if (blockingApprovalsEnabled() && eventName === 'PreToolUse' && toolNeedsApproval(matcherOf(payload))) {
      const toolName = matcherOf(payload);
      const requestId = `${agentId}:${randomUUID()}`;
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
    } else if (getIntegration(source).shouldLogUnhandledPreTool(source) && eventName === 'PreToolUse') {
      const toolName = matcherOf(payload);
      log(`qoder pretool observed without approval tool=${toolName || '<unknown>'} keys=${Object.keys(payload).sort().join(',')}`);
    }
  } catch (error) {
    log(`Hook error (${source}/${eventName}): ${error.message}`);
    if (blockingApprovalsEnabled() && eventName === 'PreToolUse' && toolNeedsApproval(matcherOf(payload))) {
      process.stdout.write(`${JSON.stringify(permissionOutput(source, eventName, false))}\n`);
    } else {
      // Passive and monitor-only hooks must never interfere with the host tool.
      process.exitCode = 0;
    }
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
  const agentId = legacyAgentId(agentType);
  const resolvedName = legacyAgentName(agentType);
  const client = new BridgeClient(agentId);
  await client.connect();
  client.send({
    type: 'agent_update',
    data: legacyAgentPayload(agentId, resolvedName, agentType, status, currentTask),
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
      if (command === 'event' && blockingApprovalsEnabled()) {
        const source = rest[0] || 'claude';
        process.stdout.write(`${JSON.stringify(permissionOutput(source, 'PreToolUse', false))}\n`);
        process.exitCode = 0;
        return;
      }
      process.exitCode = command === 'event' ? 0 : 1;
    });
}

module.exports = { runEventHook };
