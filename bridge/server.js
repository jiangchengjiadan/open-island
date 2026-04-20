const net = require('net');
const fs = require('fs');
const path = require('path');

const SOCKET_PATH = '/tmp/notch-monitor.sock';
const DEBUG_LOGS_ENABLED = process.env.NOTCH_MONITOR_DEBUG === '1';

function debugLog(...args) {
    if (DEBUG_LOGS_ENABLED) {
        console.log(...args);
    }
}

class NotchMonitorServer {
    constructor() {
        this.clients = new Set();
        this.agents = new Map();
        this.sessionPermissionGrants = new Map();
    }

    start() {
        // 清理旧的 socket 文件
        if (fs.existsSync(SOCKET_PATH)) {
            fs.unlinkSync(SOCKET_PATH);
        }

        const server = net.createServer((socket) => {
            debugLog('Client connected');
            socket.setEncoding('utf8');
            socket.buffer = '';
            this.clients.add(socket);
            this.sendSnapshot(socket);

            socket.on('data', (data) => {
                socket.buffer += data;

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
                this.clients.delete(socket);
            });

            socket.on('error', (err) => {
                console.error('Socket error:', err.message);
                this.clients.delete(socket);
            });
        });

        server.listen(SOCKET_PATH, () => {
            console.log(`Server listening on ${SOCKET_PATH}`);
            // 设置 socket 文件权限
            fs.chmodSync(SOCKET_PATH, 0o777);
        });

    }

    handleMessage(message, socket) {
        switch (message.type) {
            case 'agent_register':
                this.registerAgent(message.data);
                break;
            case 'agent_update':
                this.updateAgent(message.data);
                break;
            case 'agent_unregister':
                this.unregisterAgent(message.data.id);
                break;
            case 'permission_request':
                this.broadcastPermissionRequest(message.data);
                break;
            case 'permission_response':
                this.forwardPermissionResponse(message.data);
                break;
            default:
                console.warn('Unknown message type:', message.type);
        }
    }

    registerAgent(data) {
        const agent = {
            id: data.id || generateId(),
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
        
        this.agents.set(agent.id, agent);
        this.broadcast({ type: 'agent_registered', data: agent });
        debugLog(`Agent registered: ${agent.name}`);
    }

    updateAgent(data) {
        const agent = this.agents.get(data.id);
        if (agent) {
            Object.assign(agent, data, { lastUpdate: Date.now() });
            this.broadcast({ type: 'agent_updated', data: agent });
        } else {
            this.registerAgent(data);
        }
    }

    unregisterAgent(id) {
        if (this.agents.has(id)) {
            this.agents.delete(id);
            this.sessionPermissionGrants.delete(id);
            this.broadcast({ type: 'agent_unregistered', data: { id } });
        }
    }

    broadcastPermissionRequest(data) {
        const request = data.request || {};
        const permissionKey = request.permissionKey || permissionKeyForRequest(request);
        if (permissionKey) {
            request.permissionKey = permissionKey;
            data.request = request;
        }

        if (this.hasSessionGrant(data.agentId, permissionKey)) {
            this.forwardPermissionResponse({
                agentId: data.agentId,
                requestId: request.id,
                allowed: true,
                scope: 'session_similar',
                permissionKey,
                autoApproved: true
            });
            return;
        }

        const agent = this.agents.get(data.agentId);
        if (agent) {
            agent.needsPermission = true;
            agent.permissionRequest = request;
            this.broadcast({ type: 'permission_requested', data });
        }
    }

    forwardPermissionResponse(data) {
        const agent = this.agents.get(data.agentId);
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
        this.broadcast({ type: 'permission_responded', data });
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
            data: Array.from(this.agents.values())
        });
    }

    broadcast(message) {
        this.clients.forEach(client => {
            this.send(client, message);
        });
    }

    send(socket, message) {
        if (socket.writable) {
            socket.write(JSON.stringify(message) + '\n');
        }
    }
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

// 启动服务器
const server = new NotchMonitorServer();
server.start();

// 优雅退出
process.on('SIGINT', () => {
    console.log('\nShutting down...');
    if (fs.existsSync(SOCKET_PATH)) {
        fs.unlinkSync(SOCKET_PATH);
    }
    process.exit(0);
});
