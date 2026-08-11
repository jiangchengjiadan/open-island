#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
runtime_root="$repo_root/native/NotchMonitor/Sources/AppRuntime"

bridge_files=(server.js hook.js codex-wrapper.js utils.js)
integration_files=(index.js claude-family.js codex.js cursor.js gemini.js)
script_files=(auto-install-hooks.js install-codex-wrapper.js)

for file in "${bridge_files[@]}"; do
    cp "$repo_root/bridge/$file" "$runtime_root/bridge/$file"
done
for file in "${integration_files[@]}"; do
    cp "$repo_root/bridge/integrations/$file" "$runtime_root/bridge/integrations/$file"
done
for file in "${script_files[@]}"; do
    cp "$repo_root/scripts/$file" "$runtime_root/scripts/$file"
done

node "$repo_root/scripts/generate-runtime-manifest.js"

echo "Synchronized packaged AppRuntime from canonical sources."
