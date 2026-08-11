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
    const stats = fs.lstatSync(installPath);
    if (!stats.isFile() || stats.isSymbolicLink()) {
      throw new Error(`Refusing to replace non-regular Codex launcher at ${installPath}`);
    }
    const existing = fs.readFileSync(installPath, 'utf8');
    if (!existing.includes(managedMarker)) {
      throw new Error(`Refusing to overwrite unmanaged Codex launcher at ${installPath}`);
    }
  }
  const temporaryPath = `${installPath}.open-island.tmp.${process.pid}`;
  fs.writeFileSync(temporaryPath, script, { mode: 0o755, flag: 'wx' });
  try {
    fs.renameSync(temporaryPath, installPath);
  } catch (error) {
    try { fs.unlinkSync(temporaryPath); } catch (_) {}
    throw error;
  }
}

function main() {
  const args = process.argv.slice(2);
  if (args.includes('--status')) {
    const managed = fs.existsSync(installPath) && fs.readFileSync(installPath, 'utf8').includes(managedMarker);
    console.log(JSON.stringify({ installPath, managed }, null, 2));
    return;
  }
  if (args.includes('--uninstall')) {
    if (!fs.existsSync(installPath)) return;
    const existing = fs.readFileSync(installPath, 'utf8');
    if (!existing.includes(managedMarker)) {
      throw new Error(`Refusing to remove unmanaged Codex launcher at ${installPath}`);
    }
    fs.unlinkSync(installPath);
    console.log(`Removed managed Codex wrapper at ${installPath}`);
    return;
  }
  const realBinary = resolveRealCodexBinary();
  writeWrapper(realBinary);
  console.log(`Installed Codex wrapper at ${installPath}`);
  console.log(`Forwarding to ${realBinary}`);
}

main();
