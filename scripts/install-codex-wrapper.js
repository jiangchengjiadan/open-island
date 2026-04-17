#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const repoRoot = path.resolve(__dirname, '..');
const wrapperRuntime = path.join(repoRoot, 'bridge', 'codex-wrapper.js');
const installPath = path.join(process.env.HOME, '.local', 'bin', 'codex');
const managedMarker = 'bridge/codex-wrapper.js';

function ensureDir(filePath) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
}

function backupFile(filePath) {
  if (!fs.existsSync(filePath)) return;
  const backupPath = `${filePath}.backup.${new Date().toISOString().replace(/[:]/g, '-')}`;
  fs.copyFileSync(filePath, backupPath);
}

function resolveRealCodexBinary() {
  const output = execFileSync('/usr/bin/which', ['-a', 'codex'], { encoding: 'utf8' });
  const candidates = output
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean)
    .filter((candidate) => path.resolve(candidate) !== path.resolve(installPath));

  if (candidates.length === 0) {
    throw new Error('Could not find the real codex binary');
  }

  return candidates[0];
}

function writeWrapper(realBinary) {
  const script = `#!/bin/bash
exec "${process.execPath}" "${wrapperRuntime}" --real "${realBinary}" "$@"
`;

  ensureDir(installPath);
  if (fs.existsSync(installPath)) {
    const existing = fs.readFileSync(installPath, 'utf8');
    if (!existing.includes(managedMarker) && !existing.includes(realBinary)) {
      backupFile(installPath);
    }
  }
  fs.writeFileSync(installPath, script, { mode: 0o755 });
}

function main() {
  const realBinary = resolveRealCodexBinary();
  writeWrapper(realBinary);
  console.log(`Installed Codex wrapper at ${installPath}`);
  console.log(`Forwarding to ${realBinary}`);
}

main();
