const net = require('net');
const fs = require('fs');
const { randomUUID } = require('crypto');

const SOCKET_PATH = process.env.NOTCH_MONITOR_SOCKET_PATH || `/tmp/open-island-${process.getuid()}.sock`;
const DEBUG_LOGS_ENABLED = process.env.NOTCH_MONITOR_DEBUG === '1';
const CLEANUP_INTERVAL_MS = 15_000;
const COMPLETED_AGENT_TTL_MS = 60_000;
const DEAD_PID_GRACE_MS = 30_000;
const MISSING_PID_AGENT_TTL_MS = 10 * 60_000;
const MAX_FRAME_BYTES = 256 * 1024;
const MAX_PENDING_PER_AGENT = 32;
const UI_TOKEN = readUICapability();
const OWNER_PATH = `${SOCKET_PATH}.owner`;
const INSTANCE_ID = randomUUID();

function debugLog(...args) {
    if (DEBUG_LOGS_ENABLED) {
        console.log(...args);
    }
}

function readUICapability() {
    const descriptor = Number(process.env.NOTCH_MONITOR_UI_TOKEN_FD);
    if (!Number.isInteger(descriptor) || descriptor < 0) return '';
    try {
        return fs.readFileSync(descriptor, 'utf8').trim();
    } catch (_) {
        return '';
    }
}

class NotchMonitorServer {
    constructor() {
        this.clients = new Set();
        this.agents = new Map();
        this.sessionPermissionGrants = new Map();
        this.pendingPermissionQueues = new Map();
        this.pendingPermissionOwners = new Map();
        this.clientMetadata = new WeakMap();
        this.cleanupTimer = null;
        this.server = null;
    }

    start() {
        prepareSocketPath();
        fs.writeFileSync(OWNER_PATH, JSON.stringify({ pid: process.pid, instanceId: INSTANCE_ID }), { mode: 0o600, flag: 'wx' });
        const server = net.createServer((socket) => {
            debugLog('Client connected');
            socket.setEncoding('utf8');
            socket.buffer = '';
            this.clients.add(socket);
            this.clientMetadata.set(socket, { role: null, authenticated: false, ownedAgents: new Set() });

            socket.on('data', (data) => {
                socket.buffer += data;
                if (Buffer.byteLength(socket.buffer, 'utf8') > MAX_FRAME_BYTES) {
                    socket.destroy(new Error('Frame exceeds maximum size'));
                    return;
                }

                let newlineIndex = socket.buffer.indexOf('\n');
                while (newlineIndex !== -1) {
                    const rawMessage = socket.buffer.slice(0, newlineIndex).trim();
                    socket.buffer = socket.buffer.slice(newlineIndex + 1);

                    if (rawMessage) {
                        try {
                            const message = JSON.parse(rawMessage);
                            this.handleMessage(message, socket);
                        } catch (e) {
                            console.error('Invalid JSON:', e.message);
                        }
                    }

                    newlineIndex = socket.buffer.indexOf('\n');
                }
            });

            socket.on('end', () => {
                debugLog('Client disconnected');
                this.handleClientDisconnect(socket);
            });

            socket.on('error', (err) => {
                console.error('Socket error:', err.message);
                this.handleClientDisconnect(socket);
            });
        });

        server.on('error', (error) => {
            console.error(`Bridge server error: ${error.message}`);
            process.exitCode = 1;
            server.close();
            cleanupOwnedSocket();
        });

        server.listen(SOCKET_PATH, () => {
            console.log(`Server listening on ${SOCKET_PATH}`);
            // 限制为当前用户可访问，避免本机其他用户误连本地 bridge。
            fs.chmodSync(SOCKET_PATH, 0o700);
        });
        this.server = server;

        this.cleanupTimer = setInterval(() => {
            this.cleanupStaleAgents();
        }, CLEANUP_INTERVAL_MS);

        if (typeof this.cleanupTimer.unref === 'function') {
            this.cleanupTimer.unref();
        }

    }

    handleMessage(message, socket) {
        const metadata = this.clientMetadata.get(socket);
        if (!metadata) return;

        if (!metadata.authenticated) {
            if (message.type !== 'hello') {
                socket.destroy(new Error('Authentication required'));
                return;
            }
            this.authenticateClient(message.data || {}, socket, metadata);
            return;
        }

        switch (message.type) {
            case 'agent_register':
                if (!this.canPublishAgents(metadata)) return;
                this.registerAgent(message.data, socket);
                break;
            case 'agent_update':
                if (!this.canPublishAgents(metadata)) return;
                if (!this.mayClaimAgent(metadata, message.data)) return;
                this.updateAgent(message.data, socket);
                break;
            case 'agent_unregister':
                if (!this.ownsAgent(metadata, message.data?.id)) return;
                this.unregisterAgent(message.data.id);
                break;
            case 'permission_request':
                if (metadata.role !== 'hook' || !this.ownsAgent(metadata, message.data?.agentId)) return;
                this.broadcastPermissionRequest(message.data, socket);
                break;
            case 'permission_response':
                if (metadata.role !== 'ui') return;
                this.forwardPermissionResponse(message.data);
                break;
            default:
                console.warn('Unknown message type:', message.type);
        }
    }

    authenticateClient(data, socket, metadata) {
        const role = data.role;
        const supportedRoles = new Set(['ui', 'hook', 'wrapper', 'legacy']);
        if (data.version !== 1 || !supportedRoles.has(role)) {
            socket.destroy(new Error('Unsupported client hello'));
            return;
        }
        if (role === 'ui' && (!UI_TOKEN || data.token !== UI_TOKEN)) {
            socket.destroy(new Error('Invalid UI capability'));
            return;
        }
        metadata.role = role;
        metadata.authenticated = true;
        this.send(socket, { type: 'hello_ack', data: { version: 1, role } });
        if (role === 'ui') this.sendSnapshot(socket);
    }

    canPublishAgents(metadata) {
        return ['hook', 'wrapper', 'legacy'].includes(metadata.role);
    }

    ownsAgent(metadata, agentId) {
        return typeof agentId === 'string' && metadata.ownedAgents.has(agentId);
    }

    mayClaimAgent(metadata, data) {
        if (!data || typeof data.id !== 'string') return false;
        const existing = this.agents.get(data.id);
        if (!existing || !existing.ownerSocket || this.ownsAgent(metadata, data.id)) return true;
        return Number.isInteger(data.pid) && data.pid > 0 && data.pid === existing.pid;
    }

    registerAgent(data, socket) {
        if (!data || typeof data !== 'object') return;
        const metadata = this.clientMetadata.get(socket);
        const id = data.id || generateId();
        if (this.agents.has(id) && !metadata.ownedAgents.has(id)) return;
        const agent = {
            id,
            name: data.name,
            type: data.type,
            status: data.status || 'running',
            terminal: data.terminal,
            terminalApp: data.terminalApp || null,
            tty: data.tty || data.terminal || null,
            cwd: data.cwd || null,
            pid: data.pid || null,
            terminalTitleToken: data.terminalTitleToken || null,
            parentPid: data.parentPid || null,
            parentCommand: data.parentCommand || null,
            processChain: data.processChain || null,
            environmentHints: data.environmentHints || null,
            jetbrainsContext: data.jetbrainsContext || null,
            currentTask: data.currentTask,
            lastUpdate: Date.now(),
            needsPermission: false
        };
        metadata.ownedAgents.add(agent.id);
        agent.ownerSocket = socket;
        this.sessionPermissionGrants.delete(agent.id);
        this.agents.set(agent.id, agent);
        this.broadcastToUI({ type: 'agent_registered', data: serializableAgent(agent) });
        debugLog(`Agent registered: ${agent.name}`);
    }

    updateAgent(data, socket) {
        const agent = this.agents.get(data.id);
        if (agent) {
            const metadata = this.clientMetadata.get(socket);
            if (agent.pid && data.pid && agent.pid !== data.pid) {
                this.sessionPermissionGrants.delete(agent.id);
            }
            metadata.ownedAgents.add(agent.id);
            agent.ownerSocket = socket;
            Object.assign(agent, data, { lastUpdate: Date.now() });
            this.broadcastToUI({ type: 'agent_updated', data: serializableAgent(agent) });
        } else {
            this.registerAgent(data, socket);
        }
    }

    unregisterAgent(id) {
        if (this.agents.has(id)) {
            this.agents.delete(id);
            this.sessionPermissionGrants.delete(id);
            this.pendingPermissionQueues.delete(id);
            this.pendingPermissionOwners.delete(id);
            this.broadcastToUI({ type: 'agent_unregistered', data: { id } });
        }
    }

    broadcastPermissionRequest(data, ownerSocket) {
        const request = data.request || {};
        request.nonce = randomUUID();
        const permissionKey = request.permissionKey || permissionKeyForRequest(request);
        if (permissionKey) {
            request.permissionKey = permissionKey;
            data.request = request;
        }

        if (this.hasSessionGrant(data.agentId, permissionKey)) {
            this.completePermissionRequest({
                agentId: data.agentId,
                requestId: request.id,
                allowed: true,
                scope: 'session_similar',
                permissionKey,
                autoApproved: true
            }, true, ownerSocket);
            return;
        }

        const agent = this.agents.get(data.agentId);
        if (agent) {
            if (agent.needsPermission && agent.permissionRequest) {
                this.enqueuePermissionRequest(data.agentId, request, ownerSocket);
                debugLog(`Queued permission request agent=${data.agentId} request=${request.id}`);
                return;
            }

            this.presentPermissionRequest(data.agentId, request, ownerSocket);
        }
    }

    forwardPermissionResponse(data) {
        const agent = this.agents.get(data.agentId);
        if (!agent || !agent.permissionRequest || !agent.permissionRequest.nonce || data.requestId !== agent.permissionRequest.id || data.nonce !== agent.permissionRequest.nonce) {
            debugLog(`Ignored stale permission response agent=${data.agentId} request=${data.requestId}`);
            return false;
        }
        return this.completePermissionRequest(data, false);
    }

    completePermissionRequest(data, autoApproved, explicitOwnerSocket = null) {
        const agent = this.agents.get(data.agentId);
        if (!agent) return false;
        const currentRequest = agent.permissionRequest;
        if (!autoApproved && (!currentRequest || data.requestId !== currentRequest.id)) return false;
        const permissionKey = data.permissionKey || agent?.permissionRequest?.permissionKey || null;
        const scope = data.scope || 'once';

        if (data.allowed && scope === 'session_similar' && permissionKey) {
            this.addSessionGrant(data.agentId, permissionKey);
            data.permissionKey = permissionKey;
        }

        if (agent) {
            agent.needsPermission = false;
            agent.permissionRequest = null;
        }
        this.broadcastToUI({
            type: 'interaction_responded',
            data: buildPermissionInteractionResponse(data, permissionKey)
        });
        const ownerSocket = explicitOwnerSocket || this.pendingPermissionOwners.get(data.requestId) || agent.ownerSocket;
        this.send(ownerSocket, { type: 'permission_responded', data });
        this.broadcastToUI({ type: 'permission_responded', data });
        this.pendingPermissionOwners.delete(data.requestId);

        this.presentNextQueuedPermission(data.agentId);
        return true;
    }

    addSessionGrant(agentId, permissionKey) {
        if (!agentId || !permissionKey) return;
        if (!this.sessionPermissionGrants.has(agentId)) {
            this.sessionPermissionGrants.set(agentId, new Set());
        }
        this.sessionPermissionGrants.get(agentId).add(permissionKey);
    }

    hasSessionGrant(agentId, permissionKey) {
        if (!agentId || !permissionKey) return false;
        return this.sessionPermissionGrants.get(agentId)?.has(permissionKey) === true;
    }

    sendSnapshot(socket) {
        this.send(socket, {
            type: 'agent_snapshot',
            data: Array.from(this.agents.values()).map(serializableAgent)
        });
    }

    broadcast(message) {
        this.clients.forEach(client => {
            this.send(client, message);
        });
    }

    broadcastToUI(message) {
        this.clients.forEach(client => {
            if (this.clientMetadata.get(client)?.role === 'ui') this.send(client, message);
        });
    }

    send(socket, message) {
        if (socket?.writable) {
            socket.write(JSON.stringify(message) + '\n');
        }
    }

    enqueuePermissionRequest(agentId, request, ownerSocket) {
        if (!this.pendingPermissionQueues.has(agentId)) {
            this.pendingPermissionQueues.set(agentId, []);
        }
        const queue = this.pendingPermissionQueues.get(agentId);
        if (queue.length >= MAX_PENDING_PER_AGENT) {
            this.send(ownerSocket, { type: 'permission_responded', data: { agentId, requestId: request.id, allowed: false, reason: 'queue_full' } });
            return;
        }
        queue.push({ request, ownerSocket });
    }

    presentPermissionRequest(agentId, request, ownerSocket) {
        const agent = this.agents.get(agentId);
        if (!agent) return;

        agent.needsPermission = true;
        agent.permissionRequest = request;
        this.pendingPermissionOwners.set(request.id, ownerSocket);
        agent.lastUpdate = Date.now();
        this.broadcastToUI({
            type: 'interaction_requested',
            data: {
                agentId,
                request: buildPermissionInteractionRequest(request),
            },
        });
        this.broadcastToUI({
            type: 'permission_requested',
            data: {
                agentId,
                request,
            },
        });
    }

    presentNextQueuedPermission(agentId) {
        const queue = this.pendingPermissionQueues.get(agentId);
        if (!queue || queue.length === 0) {
            this.pendingPermissionQueues.delete(agentId);
            return;
        }

        const next = queue.shift();
        if (!next) {
            this.pendingPermissionQueues.delete(agentId);
            return;
        }

        if (queue.length === 0) {
            this.pendingPermissionQueues.delete(agentId);
        }

        this.presentPermissionRequest(agentId, next.request, next.ownerSocket);
    }

    handleClientDisconnect(socket) {
        this.clients.delete(socket);
        const metadata = this.clientMetadata.get(socket);
        if (!metadata) return;
        if (metadata.role === 'ui') {
            for (const agent of this.agents.values()) {
                if (!agent.permissionRequest) continue;
                const queued = this.pendingPermissionQueues.get(agent.id) || [];
                this.pendingPermissionQueues.delete(agent.id);
                for (const entry of queued) {
                    this.send(entry.ownerSocket, {
                        type: 'permission_responded',
                        data: { agentId: agent.id, requestId: entry.request.id, allowed: false, reason: 'ui_disconnected' },
                    });
                }
                this.completePermissionRequest({
                    agentId: agent.id,
                    requestId: agent.permissionRequest.id,
                    nonce: agent.permissionRequest.nonce,
                    allowed: false,
                    scope: 'once',
                    reason: 'ui_disconnected',
                }, false);
            }
        }
        for (const agent of this.agents.values()) {
            const queue = this.pendingPermissionQueues.get(agent.id) || [];
            const remaining = queue.filter(entry => entry.ownerSocket !== socket);
            if (remaining.length === 0) this.pendingPermissionQueues.delete(agent.id);
            else this.pendingPermissionQueues.set(agent.id, remaining);

            if (agent.permissionRequest && this.pendingPermissionOwners.get(agent.permissionRequest.id) === socket) {
                this.completePermissionRequest({
                    agentId: agent.id,
                    requestId: agent.permissionRequest.id,
                    nonce: agent.permissionRequest.nonce,
                    allowed: false,
                    scope: 'once',
                    reason: 'requester_disconnected',
                }, false, socket);
            }
        }
        for (const agentId of metadata.ownedAgents) {
            const agent = this.agents.get(agentId);
            if (agent?.ownerSocket !== socket) continue;
            agent.ownerSocket = null;
        }
        this.clientMetadata.delete(socket);
    }

    cleanupStaleAgents() {
        const now = Date.now();

        for (const [id, agent] of this.agents.entries()) {
            const age = now - (agent.lastUpdate || 0);
            const hasLivePID = isLiveProcess(agent.pid);

            if (agent.needsPermission && age < MISSING_PID_AGENT_TTL_MS) {
                continue;
            }

            if (agent.status === 'completed') {
                if (age > COMPLETED_AGENT_TTL_MS) {
                    debugLog(`Cleaning completed agent ${id} age=${age}`);
                    this.unregisterAgent(id);
                }
                continue;
            }

            if (agent.pid && !hasLivePID && age > DEAD_PID_GRACE_MS) {
                debugLog(`Cleaning dead-pid agent ${id} pid=${agent.pid} age=${age}`);
                this.unregisterAgent(id);
                continue;
            }

            if (!agent.pid && age > MISSING_PID_AGENT_TTL_MS) {
                debugLog(`Cleaning stale no-pid agent ${id} age=${age}`);
                this.unregisterAgent(id);
            }
        }
    }

    stop() {
        if (this.cleanupTimer) {
            clearInterval(this.cleanupTimer);
            this.cleanupTimer = null;
        }
        this.server?.close(() => {
            try {
                cleanupOwnedSocket();
            } catch (error) {
                debugLog(`Socket cleanup failed: ${error.message}`);
            }
        });
        this.server = null;
    }
}

function readSocketOwner() {
    try {
        return JSON.parse(fs.readFileSync(OWNER_PATH, 'utf8'));
    } catch (_) {
        return null;
    }
}

function prepareSocketPath() {
    const owner = readSocketOwner();
    if (owner && isLiveProcess(owner.pid)) {
        throw new Error(`Bridge already running with pid ${owner.pid}`);
    }
    if (fs.existsSync(SOCKET_PATH) && !owner) {
        throw new Error('Socket exists without a verifiable owner; refusing unsafe cleanup');
    }
    if (fs.existsSync(SOCKET_PATH)) fs.unlinkSync(SOCKET_PATH);
    if (fs.existsSync(OWNER_PATH)) fs.unlinkSync(OWNER_PATH);
}

function cleanupOwnedSocket() {
    const owner = readSocketOwner();
    if (owner?.pid !== process.pid || owner?.instanceId !== INSTANCE_ID) return;
    if (fs.existsSync(SOCKET_PATH)) fs.unlinkSync(SOCKET_PATH);
    if (fs.existsSync(OWNER_PATH)) fs.unlinkSync(OWNER_PATH);
}

function serializableAgent(agent) {
    const { ownerSocket, ...data } = agent;
    return data;
}

function generateId() {
    return Math.random().toString(36).substring(2, 15);
}

function normalizePermissionPart(value) {
    if (value == null) return '';
    return String(value).trim().replace(/\s+/g, ' ');
}

function permissionKeyForRequest(request) {
    const type = normalizePermissionPart(request?.type);
    if (!type) return '';

    if (['Edit', 'Write', 'MultiEdit', 'NotebookEdit'].includes(type)) {
        return `${type}:file:${normalizePermissionPart(request.filePath || request.message)}`;
    }

    if (type === 'Bash') {
        return `${type}:command:${normalizePermissionPart(request.command || request.message)}`;
    }

    return `${type}:input:${normalizePermissionPart(request.message)}`;
}

function buildPermissionInteractionRequest(request) {
    const type = normalizePermissionPart(request?.type) || 'Permission';
    return {
        id: request?.id || generateId(),
        kind: 'permission',
        title: `Allow ${type}`,
        message: request?.message || null,
        markdown: null,
        options: [
            { id: 'allow', value: 'allow', title: 'Allow', detail: null },
            { id: 'deny', value: 'deny', title: 'Deny', detail: null },
            { id: 'allow_similar', value: 'allow_similar', title: 'Allow Similar', detail: 'Session only' },
        ],
        textResponse: {
            enabled: false,
            placeholder: null,
        },
        metadata: {
            toolName: type,
            command: request?.command || null,
            filePath: request?.filePath || null,
            permissionKey: request?.permissionKey || null,
            nonce: request?.nonce || null,
        },
        timestamp: request?.timestamp || Date.now(),
    };
}

function buildPermissionInteractionResponse(data, permissionKey) {
    return {
        agentId: data.agentId,
        requestId: data.requestId,
        selectedOption: data.allowed ? (data.scope === 'session_similar' ? 'allow_similar' : 'allow') : 'deny',
        text: null,
        scope: data.scope || 'once',
        metadata: {
            permissionKey: permissionKey || null,
            autoApproved: Boolean(data.autoApproved),
        }
    };
}

function isLiveProcess(pid) {
    const numericPID = Number(pid);
    if (!Number.isInteger(numericPID) || numericPID <= 0) {
        return false;
    }

    try {
        process.kill(numericPID, 0);
        return true;
    } catch (error) {
        return error.code !== 'ESRCH';
    }
}

if (require.main === module) {
    const server = new NotchMonitorServer();
    server.start();

    process.on('SIGINT', () => {
        console.log('\nShutting down...');
        server.stop();
    });
    process.on('SIGTERM', () => {
        server.stop();
    });
}

module.exports = {
    NotchMonitorServer,
    permissionKeyForRequest,
};
