const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const hookPath = path.join(__dirname, '..', 'hook.js');

function runHook(stdin) {
    return runSourceHook('claude', stdin, true);
}

function runSourceHook(source, stdin, enableBlocking = false) {
    return spawnSync(process.execPath, [hookPath, 'event', source], {
        input: stdin,
        encoding: 'utf8',
        env: {
            ...process.env,
            NOTCH_MONITOR_SOCKET_PATH: `/tmp/open-island-missing-${process.pid}.sock`,
            NOTCH_MONITOR_ENABLE_BLOCKING_APPROVALS: enableBlocking ? '1' : '0',
        },
    });
}

test('blocking hook emits deny when the bridge is unavailable', () => {
    const result = runHook(JSON.stringify({
        hook_event_name: 'PreToolUse',
        tool_name: 'Bash',
        tool_input: { command: 'true' },
    }));
    const output = JSON.parse(result.stdout.trim());
    assert.equal(output.hookSpecificOutput.permissionDecision, 'deny');
});

test('monitor-only hooks stay passive when the bridge is unavailable', () => {
    const claude = runSourceHook('claude', JSON.stringify({
        hook_event_name: 'PreToolUse',
        tool_name: 'Bash',
        tool_input: { command: 'true' },
    }));
    assert.equal(claude.status, 0);
    assert.equal(claude.stdout, '');

    const cursor = runSourceHook('cursor', JSON.stringify({
        hook_event_name: 'beforeShellExecution',
        command: 'true',
    }));
    assert.equal(cursor.status, 0);
    assert.equal(cursor.stdout, '');

    const gemini = runSourceHook('gemini', JSON.stringify({ hook_event_name: 'SessionStart' }));
    assert.equal(gemini.status, 0);
    assert.equal(gemini.stdout, '');
});

test('malformed hook input emits a conservative deny', () => {
    const result = runHook('{invalid');
    const output = JSON.parse(result.stdout.trim());
    assert.equal(output.hookSpecificOutput.permissionDecision, 'deny');
    assert.equal(result.status, 0);
});

test('malformed monitor-only input stays passive', () => {
    const result = runSourceHook('claude', '{invalid');
    assert.equal(result.status, 0);
    assert.equal(result.stdout, '');
});
