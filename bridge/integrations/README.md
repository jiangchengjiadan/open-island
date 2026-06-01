# Bridge Integrations

This directory holds source-specific hook behavior that should not continue to grow inside `bridge/hook.js`.

Current first-pass integrations:

- `claude-family.js`
  - used by `claude`
  - also reused by `qoder`
- `codex.js`
- `cursor.js`
- `gemini.js`

Each integration is responsible for:

- session id/name extraction differences
- hook stdout compatibility
- any source-specific fallback logging behavior

Follow-up integrations should add a new module here and register it in `index.js`.
