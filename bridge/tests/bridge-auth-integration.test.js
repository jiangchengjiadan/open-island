const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const net = require('node:net');
const os = require('node:os');
const path = require('node:path');
const { spawn } = require('node:child_process');

const serverPath = path.resolve(__dirname, '..', 'server.js');

function waitForSocket(socketPath, child, stderr, timeoutMs = 3000) {
    const deadline = Date.now() + timeoutMs;
    return new Promise((resolve, reject) => {
        const poll = () => {
            if (fs.existsSync(socketPath)) return resolve();
            if (child.exitCode !== null) return reject(new Error(stderr.value || `bridge exited ${child.exitCode}`));
            if (Date.now() >= deadline) return reject(new Error('bridge socket did not appear'));
            setTimeout(poll, 20);
        };
        poll();
    });
}

function readOneMessage(socket) {
    return new Promise((resolve, reject) => {
        let buffer = '';
        socket.setEncoding('utf8');
        socket.on('data', (chunk) => {
            buffer += chunk;
            const newline = buffer.indexOf('\n');
            if (newline === -1) return;
            resolve(JSON.parse(buffer.slice(0, newline)));
        });
        socket.once('error', reject);
    });
}

test('bridge reads UI capability from inherited stdin and authenticates UI', async (t) => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'open-island-bridge-'));
    const socketPath = path.join(root, 'bridge.sock');
    const token = 'ephemeral-test-capability';
    const child = spawn(process.execPath, [serverPath], {
        stdio: ['pipe', 'ignore', 'pipe'],
        env: { ...process.env, NOTCH_MONITOR_SOCKET_PATH: socketPath, NOTCH_MONITOR_UI_TOKEN_FD: '0' },
    });
    const stderr = { value: '' };
    child.stderr.on('data', (chunk) => { stderr.value += chunk.toString(); });
    t.after(() => {
        child.kill('SIGTERM');
        fs.rmSync(root, { recursive: true, force: true });
    });
    child.stdin.end(token);
    try {
        await waitForSocket(socketPath, child, stderr);
    } catch (error) {
        if (/EPERM|operation not permitted/i.test(error.message)) {
            t.skip('sandbox does not permit Unix socket listen');
            return;
        }
        throw error;
    }

    const socket = net.createConnection(socketPath);
    await new Promise((resolve, reject) => {
        socket.once('connect', resolve);
        socket.once('error', reject);
    });
    socket.write(`${JSON.stringify({ type: 'hello', data: { version: 1, role: 'ui', token } })}\n`);
    const ack = await readOneMessage(socket);
    assert.equal(ack.type, 'hello_ack');
    assert.equal(ack.data.role, 'ui');
    socket.end();
});
