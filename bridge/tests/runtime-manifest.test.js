const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { createHash } = require('node:crypto');

const runtimeRoot = path.resolve(__dirname, '..', '..', 'native', 'NotchMonitor', 'Sources', 'AppRuntime');

test('packaged runtime manifest matches every declared file', () => {
    const manifest = JSON.parse(fs.readFileSync(path.join(runtimeRoot, 'runtime-manifest.json'), 'utf8'));
    assert.equal(manifest.version, 1);
    assert.equal(manifest.protocolVersion, 1);
    for (const [relativePath, expectedHash] of Object.entries(manifest.files)) {
        const data = fs.readFileSync(path.join(runtimeRoot, relativePath));
        assert.equal(createHash('sha256').update(data).digest('hex'), expectedHash, relativePath);
    }
});
