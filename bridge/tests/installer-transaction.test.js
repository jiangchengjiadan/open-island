const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const installer = path.resolve(__dirname, '..', '..', 'scripts', 'auto-install-hooks.js');

function workspace() {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'open-island-installer-'));
    const home = path.join(root, 'home with spaces');
    const state = path.join(root, 'state');
    fs.mkdirSync(path.join(home, '.claude'), { recursive: true });
    return { root, home, state };
}

function run(args, env, extraEnvironment = {}) {
    return spawnSync(process.execPath, [installer, ...args], {
        encoding: 'utf8',
        env: { ...process.env, HOME: env.home, XDG_STATE_HOME: env.state, ...extraEnvironment },
    });
}

test('plan is read-only and apply/uninstall preserve foreign Claude hooks', () => {
    const env = workspace();
    const settingsPath = path.join(env.home, '.claude', 'settings.json');
    const planPath = path.join(env.root, 'plan.json');
    const foreign = { matcher: '*', hooks: [{ type: 'command', command: '/usr/bin/foreign-hook' }] };
    fs.writeFileSync(settingsPath, JSON.stringify({ hooks: { PreToolUse: [foreign] } }));
    const before = fs.readFileSync(settingsPath, 'utf8');

    const plan = run(['--tools', 'claude', '--plan-file', planPath], env);
    assert.equal(plan.status, 0, plan.stderr);
    assert.equal(fs.readFileSync(settingsPath, 'utf8'), before);

    const apply = run(['--apply', '--plan-file', planPath], env);
    assert.equal(apply.status, 0, apply.stderr);
    const installed = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));
    assert.equal(installed.hooks.PreToolUse.some((entry) => entry.hooks?.some((hook) => hook.command.includes('OPEN_ISLAND_MANAGED=1'))), true);
    assert.equal(installed.hooks.PreToolUse.some((entry) => entry.hooks?.some((hook) => hook.command === '/usr/bin/foreign-hook')), true);
    const uninstall = run(['--uninstall', '--tools', 'claude'], env);
    assert.equal(uninstall.status, 0, uninstall.stderr);
    const remaining = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));
    assert.equal(remaining.hooks.PreToolUse.some((entry) => entry.hooks?.some((hook) => hook.command.includes('hook.js'))), false);
    assert.equal(remaining.hooks.PreToolUse.some((entry) => entry.hooks?.some((hook) => hook.command === '/usr/bin/foreign-hook')), true);

    fs.rmSync(env.root, { recursive: true, force: true });
});

test('uninstall uses the installed command fingerprint across environment changes', () => {
    const env = workspace();
    const settingsPath = path.join(env.home, '.claude', 'settings.json');
    const planPath = path.join(env.root, 'plan.json');
    const blocking = { NOTCH_MONITOR_ENABLE_BLOCKING_APPROVALS: '1' };
    assert.equal(run(['--tools', 'claude', '--plan-file', planPath], env, blocking).status, 0);
    assert.equal(run(['--apply', '--plan-file', planPath], env, blocking).status, 0);
    assert.match(fs.readFileSync(settingsPath, 'utf8'), /NOTCH_MONITOR_ENABLE_BLOCKING_APPROVALS=1/);

    const uninstall = run(['--uninstall', '--tools', 'claude'], env);
    assert.equal(uninstall.status, 0, uninstall.stderr);
    assert.doesNotMatch(fs.readFileSync(settingsPath, 'utf8'), /OPEN_ISLAND_MANAGED=1/);
    const manifest = JSON.parse(fs.readFileSync(path.join(env.state, 'open-island', 'hook-manifest.json'), 'utf8'));
    assert.deepEqual(manifest.tools, []);
    assert.deepEqual(manifest.ownership, {});
    fs.rmSync(env.root, { recursive: true, force: true });
});

test('apply upgrades an owned command fingerprint without leaving the old blocking hook', () => {
    const env = workspace();
    const settingsPath = path.join(env.home, '.claude', 'settings.json');
    const blockingPlan = path.join(env.root, 'blocking-plan.json');
    const passivePlan = path.join(env.root, 'passive-plan.json');
    const blocking = { NOTCH_MONITOR_ENABLE_BLOCKING_APPROVALS: '1' };
    assert.equal(run(['--tools', 'claude', '--plan-file', blockingPlan], env, blocking).status, 0);
    assert.equal(run(['--apply', '--plan-file', blockingPlan], env, blocking).status, 0);

    assert.equal(run(['--tools', 'claude', '--plan-file', passivePlan], env).status, 0);
    const upgrade = run(['--apply', '--plan-file', passivePlan], env);
    assert.equal(upgrade.status, 0, upgrade.stderr);
    const content = fs.readFileSync(settingsPath, 'utf8');
    assert.doesNotMatch(content, /NOTCH_MONITOR_ENABLE_BLOCKING_APPROVALS=1/);
    const settings = JSON.parse(content);
    assert.equal(settings.hooks.PreToolUse.filter((entry) => entry.hooks?.some((hook) => hook.command.includes('OPEN_ISLAND_MANAGED=1'))).length, 1);

    const uninstall = run(['--uninstall', '--tools', 'claude'], env);
    assert.equal(uninstall.status, 0, uninstall.stderr);
    assert.doesNotMatch(fs.readFileSync(settingsPath, 'utf8'), /OPEN_ISLAND_MANAGED=1/);
    fs.rmSync(env.root, { recursive: true, force: true });
});

test('uninstall preserves a user-modified managed command and keeps manifest ownership', () => {
    const env = workspace();
    const settingsPath = path.join(env.home, '.claude', 'settings.json');
    const planPath = path.join(env.root, 'plan.json');
    assert.equal(run(['--tools', 'claude', '--plan-file', planPath], env).status, 0);
    assert.equal(run(['--apply', '--plan-file', planPath], env).status, 0);
    const settings = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));
    settings.hooks.PreToolUse[0].hooks[0].command = 'OPEN_ISLAND_MANAGED=1 user-modified-command';
    fs.writeFileSync(settingsPath, JSON.stringify(settings));

    const uninstall = run(['--uninstall', '--tools', 'claude'], env);
    assert.notEqual(uninstall.status, 0);
    assert.match(uninstall.stderr, /Ownership conflict/);
    assert.match(fs.readFileSync(settingsPath, 'utf8'), /user-modified-command/);
    const manifest = JSON.parse(fs.readFileSync(path.join(env.state, 'open-island', 'hook-manifest.json'), 'utf8'));
    assert.deepEqual(manifest.tools, ['claude']);
    assert.equal(typeof manifest.ownership.claude.command, 'string');
    fs.rmSync(env.root, { recursive: true, force: true });
});

test('apply rejects a stale plan after user configuration changes', () => {
    const env = workspace();
    const settingsPath = path.join(env.home, '.claude', 'settings.json');
    const planPath = path.join(env.root, 'plan.json');
    fs.writeFileSync(settingsPath, JSON.stringify({ hooks: {} }));
    assert.equal(run(['--tools', 'claude', '--plan-file', planPath], env).status, 0);
    fs.writeFileSync(settingsPath, JSON.stringify({ hooks: {}, userChange: true }));
    const apply = run(['--apply', '--plan-file', planPath], env);
    assert.notEqual(apply.status, 0);
    assert.match(apply.stderr, /re-plan required/);
    fs.rmSync(env.root, { recursive: true, force: true });
});

test('apply cannot add tools that were not present in the approved plan', () => {
    const env = workspace();
    const planPath = path.join(env.root, 'plan.json');
    assert.equal(run(['--tools', 'claude', '--plan-file', planPath], env).status, 0);
    const apply = run(['--apply', '--plan-file', planPath, '--tools', 'qoder'], env);
    assert.notEqual(apply.status, 0);
    assert.equal(fs.existsSync(path.join(env.home, '.qoder', 'settings.json')), false);
    assert.equal(fs.existsSync(path.join(env.home, '.claude', 'settings.json')), false);
    fs.rmSync(env.root, { recursive: true, force: true });
});

test('unknown tools are rejected before any configuration is written', () => {
    const env = workspace();
    const planPath = path.join(env.root, 'plan.json');
    const result = run(['--tools', 'claude,unknown', '--plan-file', planPath], env);
    assert.notEqual(result.status, 0);
    assert.equal(fs.existsSync(path.join(env.home, '.claude', 'settings.json')), false);
    fs.rmSync(env.root, { recursive: true, force: true });
});

test('manifest failure rolls back every configuration change', () => {
    const env = workspace();
    const settingsPath = path.join(env.home, '.claude', 'settings.json');
    const planPath = path.join(env.root, 'plan.json');
    fs.writeFileSync(settingsPath, JSON.stringify({ hooks: {}, preserved: true }));
    const before = fs.readFileSync(settingsPath, 'utf8');
    assert.equal(run(['--tools', 'claude', '--plan-file', planPath], env).status, 0);
    fs.rmSync(env.state, { recursive: true, force: true });
    fs.writeFileSync(env.state, 'not-a-directory');
    const apply = run(['--apply', '--plan-file', planPath], env);
    assert.notEqual(apply.status, 0);
    assert.equal(fs.readFileSync(settingsPath, 'utf8'), before);
    fs.rmSync(env.root, { recursive: true, force: true });
});

test('next invocation recovers a transaction interrupted by SIGKILL', () => {
    const env = workspace();
    const claudePath = path.join(env.home, '.claude', 'settings.json');
    const qoderPath = path.join(env.home, '.qoder', 'settings.json');
    const planPath = path.join(env.root, 'plan.json');
    fs.writeFileSync(claudePath, JSON.stringify({ hooks: {}, baseline: 'claude' }));
    fs.mkdirSync(path.dirname(qoderPath), { recursive: true });
    fs.writeFileSync(qoderPath, JSON.stringify({ hooks: {}, baseline: 'qoder' }));
    const claudeBefore = fs.readFileSync(claudePath, 'utf8');
    const qoderBefore = fs.readFileSync(qoderPath, 'utf8');
    assert.equal(run(['--tools', 'claude,qoder', '--plan-file', planPath], env).status, 0);

    const crashed = run(['--apply', '--plan-file', planPath], env, { OPEN_ISLAND_TEST_CRASH_AFTER_TOOL: 'claude' });
    assert.notEqual(crashed.status, 0);
    assert.notEqual(fs.readFileSync(claudePath, 'utf8'), claudeBefore);

    const recovery = run(['--status'], env);
    assert.equal(recovery.status, 0, recovery.stderr);
    assert.equal(fs.readFileSync(claudePath, 'utf8'), claudeBefore);
    assert.equal(fs.readFileSync(qoderPath, 'utf8'), qoderBefore);
    fs.rmSync(env.root, { recursive: true, force: true });
});

test('crash recovery preserves configuration edited after SIGKILL and reports a conflict', () => {
    const env = workspace();
    const claudePath = path.join(env.home, '.claude', 'settings.json');
    const planPath = path.join(env.root, 'plan.json');
    assert.equal(run(['--tools', 'claude,qoder', '--plan-file', planPath], env).status, 0);

    const crashed = run(['--apply', '--plan-file', planPath], env, { OPEN_ISLAND_TEST_CRASH_AFTER_TOOL: 'claude' });
    assert.notEqual(crashed.status, 0);
    const externallyEdited = { ...JSON.parse(fs.readFileSync(claudePath, 'utf8')), userAfterCrash: true };
    fs.writeFileSync(claudePath, JSON.stringify(externallyEdited));

    const recovery = run(['--status'], env);
    assert.notEqual(recovery.status, 0);
    assert.match(recovery.stderr, /Recovery conflict/);
    assert.equal(JSON.parse(fs.readFileSync(claudePath, 'utf8')).userAfterCrash, true);
    assert.equal(fs.existsSync(path.join(env.state, 'open-island', 'hook-journal.json')), true);
    fs.rmSync(env.root, { recursive: true, force: true });
});
