# JetBrains Multi-Window Disambiguation Plan

## Problem

Open Island can now identify JetBrains-hosted sessions correctly and bring the IDE to the foreground. However, when multiple JetBrains windows exist for the same IDE and the same project path, the current jump logic is not precise enough to select the exact window that owns the terminal session.

This is now a data problem, not a host-resolution problem.

## Evidence From Current Logs

Recent jump logs already show:

- the process tree resolves correctly to `IntelliJ IDEA` or `PyCharm`
- the JetBrains jump script returns `ok`
- the user still lands in the wrong window when multiple same-project windows exist

That means:

1. host IDE detection is working
2. JetBrains AppleScript execution is working
3. window-title matching by `cwd` is insufficient for same-project multi-window cases

## Root Cause

The current window selection logic only uses coarse identifiers:

- IDE app identity
- project path / `cwd`
- project-name derived window title tokens

When two or more windows share the same project path, these signals are not unique.

## Goal

Capture richer JetBrains session context from the hook/wrapper side so the bridge and native app can later distinguish:

- same IDE, different window
- same project, different terminal session
- same project, different shell ancestry

## Plan

### Phase 3A: Capture richer context in hook/wrapper payloads

Add new agent fields populated by `bridge/hook.js` and `bridge/codex-wrapper.js`.

Target fields:

- `parentPid`
- `parentCommand`
- `processChain`
- `environmentHints`
- `jetbrainsContext`

`jetbrainsContext` should include best-effort values such as:

- JetBrains-related env vars
- terminal emulator markers
- possible project hints
- possible window/session hints

This phase does not change jump behavior yet. It only expands observability and payload quality.

### Phase 3B: Surface the new fields in native models and logs

The Swift-side `Agent` model should accept the new fields so they can be logged and used by later jump logic.

Immediate use:

- debugging
- confirming what JetBrains actually exposes in embedded terminals

### Phase 3C: Use the richer context for final window disambiguation

After inspecting real payloads from PyCharm/IDEA terminals, implement the final matching strategy using the most reliable combination of:

- process ancestry
- JetBrains-specific environment hints
- project hints
- terminal/session hints

## Scope For This Change

This implementation executes Phase 3A and Phase 3B only.

Out of scope for now:

- final same-project multi-window selection algorithm
- changing the socket path or unrelated runtime naming
- speculative heuristics without first confirming real JetBrains context

## Validation

1. Launch Open Island.
2. Start Claude Code and Codex from:
   - different IntelliJ IDEA windows
   - different PyCharm windows
   - ideally two windows with the same project path
3. Trigger jump attempts.
4. Inspect logs and confirm the new fields are present.
5. Use those observed fields to design the final disambiguation rule.
