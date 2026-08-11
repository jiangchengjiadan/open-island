const test = require('node:test');
const assert = require('node:assert/strict');

const cursor = require('../integrations/cursor');
const gemini = require('../integrations/gemini');
const { NotchMonitorServer } = require('../server');

function writableSocket() {
    return {
        writable: true,
        messages: [],
        write(value) {
            this.messages.push(JSON.parse(value));
            return true;
        },
        destroy(error) {
            this.destroyedWith = error;
        },
    };
}

test('Cursor and Gemini adapters preserve deny decisions', () => {
    assert.equal(cursor.permissionOutput('PreToolUse', false).continue, false);
    assert.equal(gemini.permissionOutput('PreToolUse', false).continue, false);
    assert.equal(cursor.permissionOutput('PreToolUse', true).continue, true);
});

test('unauthenticated clients cannot publish messages or receive snapshots', () => {
    const server = new NotchMonitorServer();
    const socket = writableSocket();
    server.clientMetadata.set(socket, { role: null, authenticated: false, ownedAgents: new Set() });

    server.handleMessage({ type: 'permission_response', data: { allowed: true } }, socket);
    assert.match(socket.destroyedWith.message, /Authentication required/);
    assert.equal(socket.messages.length, 0);
});

test('authenticated hook clients cannot answer permission requests', () => {
    const server = new NotchMonitorServer();
    const socket = writableSocket();
    const metadata = { role: 'hook', authenticated: true, ownedAgents: new Set(['agent-1']) };
    server.clientMetadata.set(socket, metadata);
    server.agents.set('agent-1', {
        id: 'agent-1',
        needsPermission: true,
        permissionRequest: { id: 'request-current', type: 'Bash' },
        ownerSocket: socket,
    });

    server.handleMessage({
        type: 'permission_response',
        data: { agentId: 'agent-1', requestId: 'request-current', allowed: true },
    }, socket);
    assert.equal(server.agents.get('agent-1').permissionRequest.id, 'request-current');
});

test('stale permission response cannot clear the current request', () => {
    const server = new NotchMonitorServer();
    const ownerSocket = writableSocket();
    const request = { id: 'request-current', type: 'Bash', command: 'true', nonce: 'nonce-current' };
    server.agents.set('agent-1', {
        id: 'agent-1',
        needsPermission: true,
        permissionRequest: request,
        ownerSocket,
    });

    assert.equal(server.forwardPermissionResponse({
        agentId: 'agent-1',
        requestId: 'request-stale',
        allowed: true,
    }), false);
    assert.equal(server.agents.get('agent-1').permissionRequest.id, 'request-current');
    assert.equal(ownerSocket.messages.length, 0);
});

test('only the matching response completes a request', () => {
    const server = new NotchMonitorServer();
    const ownerSocket = writableSocket();
    const request = { id: 'request-current', type: 'Bash', command: 'true', nonce: 'nonce-current' };
    server.agents.set('agent-1', {
        id: 'agent-1',
        needsPermission: true,
        permissionRequest: request,
        ownerSocket,
    });

    assert.equal(server.forwardPermissionResponse({
        agentId: 'agent-1',
        requestId: 'request-current',
        nonce: 'nonce-current',
        allowed: false,
    }), true);
    assert.equal(server.agents.get('agent-1').permissionRequest, null);
    assert.equal(ownerSocket.messages.at(-1).type, 'permission_responded');
    assert.equal(ownerSocket.messages.at(-1).data.allowed, false);
});

test('a replay with the wrong nonce cannot complete a request', () => {
    const server = new NotchMonitorServer();
    const ownerSocket = writableSocket();
    server.agents.set('agent-1', {
        id: 'agent-1',
        needsPermission: true,
        permissionRequest: { id: 'request-current', type: 'Bash', nonce: 'nonce-current' },
        ownerSocket,
    });

    assert.equal(server.forwardPermissionResponse({
        agentId: 'agent-1',
        requestId: 'request-current',
        nonce: 'nonce-replayed',
        allowed: true,
    }), false);
    assert.equal(server.agents.get('agent-1').needsPermission, true);
});
