#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { createHash } = require('crypto');

const runtimeRoot = path.resolve(__dirname, '..', 'native', 'NotchMonitor', 'Sources', 'AppRuntime');
const files = [
  'bridge/server.js',
  'bridge/hook.js',
  'bridge/codex-wrapper.js',
  'bridge/utils.js',
  'bridge/integrations/index.js',
  'bridge/integrations/claude-family.js',
  'bridge/integrations/codex.js',
  'bridge/integrations/cursor.js',
  'bridge/integrations/gemini.js',
  'scripts/auto-install-hooks.js',
  'scripts/install-codex-wrapper.js',
];

const manifest = {
  version: 1,
  protocolVersion: 1,
  files: Object.fromEntries(files.map((relativePath) => {
    const data = fs.readFileSync(path.join(runtimeRoot, relativePath));
    return [relativePath, createHash('sha256').update(data).digest('hex')];
  })),
};

const target = path.join(runtimeRoot, 'runtime-manifest.json');
const temporary = `${target}.tmp.${process.pid}`;
fs.writeFileSync(temporary, `${JSON.stringify(manifest, null, 2)}\n`, { mode: 0o644, flag: 'wx' });
fs.renameSync(temporary, target);
