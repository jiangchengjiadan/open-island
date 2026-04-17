# JetBrains Terminal Title Token Plan

## Problem

Open Island can already identify the correct JetBrains host app and bring an IDE window to the foreground. It still cannot reliably route to the correct window when multiple windows exist for the same IDE and the same project path.

The current matching signals are not unique enough:

- IDE app identity
- `cwd`
- project-name-derived window title tokens

When multiple windows share the same project, all of those signals collide.

## Strategy

Inject a unique Open Island token into the JetBrains terminal title, then use that token as the primary window-matching key during jump.

This avoids guessing based only on project path or generic window titles.

## Token Design

Each monitored session gets a compact terminal title token derived from runtime-specific identifiers such as:

- source (`claude` / `codex`)
- tty
- pid
- session id when available

Example shape:

- `OI claude ttys004 p18974`
- `OI codex ttys002 p18947`

The exact format should stay compact, deterministic, and easy to search inside a window title.

## Implementation Plan

### Step 1: Add a token field to the agent model

Add a new field to the bridge/native agent payload:

- `terminalTitleToken`

This allows the jump service to prefer a unique token when it is available.

### Step 2: Inject the token from Claude and Codex JetBrains sessions

For JetBrains terminals only:

1. Compute a token for the session.
2. Write an OSC terminal-title escape sequence directly to the controlling tty.
3. Include the same token in the agent payload.

Important constraints:

- write directly to the tty device rather than normal stdout, so hook protocol output is not polluted
- keep the token injection best-effort and non-fatal

### Step 3: Prefer token-based matching in JetBrains jump logic

When `terminalTitleToken` exists:

1. search JetBrains UI windows for the token first
2. only fall back to `cwd` / project-name matching if token matching fails

## Scope For This Change

This implementation executes all three steps above.

Out of scope:

- a JetBrains plugin
- final tab/pane-level IDE integration
- changing socket paths or unrelated runtime naming

## Validation

1. Restart Open Island so updated hooks/wrappers are installed.
2. Launch Claude/Codex in two JetBrains windows for the same project.
3. Confirm logs show a `terminalTitleToken`.
4. Click jump for each session.
5. Confirm the correct window is raised based on the unique token rather than only the project name.
