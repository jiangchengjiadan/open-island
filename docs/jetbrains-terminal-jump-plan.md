# JetBrains Terminal Jump Fix Plan

## Background

Open Island can already jump from the notch panel back to sessions running in Terminal and iTerm. The same interaction is unreliable for Claude Code and Codex sessions started inside JetBrains IDE terminals such as PyCharm and IntelliJ IDEA.

The current behavior for JetBrains is usually one of these:

- the IDE is not activated at all;
- the wrong app name is used during activation;
- the IDE is activated, but the jump does not land in the expected window or terminal context.

## Current Root Causes

### 1. JetBrains host detection trusts terminal hints too early

`TerminalJumpService.AppDescriptor.resolve(for:)` currently prefers `agent.terminalApp` before walking the process tree. In JetBrains terminals the hint is often something like `JetBrains-JediTerm`, which is the embedded terminal component name rather than the real macOS application identity.

That leads to descriptors with:

- `kind = .jetBrains`
- `localizedName = "JetBrains-JediTerm"`
- `bundleIdentifier = nil`

This is not a safe identity for `NSRunningApplication` lookup or AppleScript activation.

### 2. JetBrains jump logic does not use the agent's existing routing signals

The current `jetBrainsScript` only:

- activates an app by name;
- sends a fixed keyboard shortcut.

It does not use the agent's `pid`, `cwd`, or `tty` to determine the real host IDE or the most likely destination window.

### 3. Diagnostics are not explicit enough for host-resolution failures

The jump log records the resolved descriptor but does not clearly show:

- the original terminal hint;
- whether the descriptor came from the hint or the process tree;
- which application identity was ultimately used.

This makes JetBrains-specific failures harder to confirm.

## Implementation Plan

### Phase 1: Stabilize JetBrains app resolution and activation

This phase is the immediate fix and should be implemented first.

Goals:

- resolve JetBrains sessions to the real IDE app whenever possible;
- activate the correct IDE window reliably;
- improve logs so failed jumps can be diagnosed quickly.

Changes:

1. Detect JetBrains terminal component names such as `JetBrains-JediTerm`, but do not trust them as the final application name.
2. When the terminal hint looks JetBrains-related, prefer `pid` process-tree resolution over the hint.
3. Use the resolved running application's real `bundleIdentifier` and `localizedName` for activation.
4. Update JetBrains AppleScript to activate by application id when available, and only use UI scripting as a secondary step.
5. Expand jump logging to include:
   - raw terminal hint
   - resolved app name
   - resolved bundle id
   - pid used for lookup

Expected result:

- clicking a PyCharm or IntelliJ-backed agent reliably brings the correct IDE to the foreground;
- exact terminal-tab targeting is still best-effort, but the user lands in the right app/window much more consistently.

### Phase 2: Improve JetBrains window targeting

This phase should be done after phase 1 is verified.

Goals:

- pick the most likely IDE window when multiple JetBrains windows are open;
- use existing metadata such as `cwd` to prefer the matching project window.

Changes:

1. Use `cwd` and project-directory basename to match JetBrains window titles where possible.
2. Add fallback heuristics for matching IDE windows by visible title or recent activation order.
3. Keep the behavior non-destructive: prefer focusing a likely window over sending broad keyboard automation blindly.

Expected result:

- better routing when multiple PyCharm or IDEA windows are open.

Status:

- in progress
- initial implementation uses `cwd`-derived project tokens to match JetBrains window titles
- if no matching window title is found, the behavior falls back to activating the IDE app only

### Phase 3: Add stronger session metadata from the hook side

This phase is optional, but it will improve precision if phase 2 is still not good enough.

Candidate additions from the hook/wrapper side:

- top-level host app bundle id;
- project name or project root basename;
- richer process ancestry diagnostics;
- raw terminal component name separate from resolved app identity.

Expected result:

- Swift-side jump logic can stop guessing based on partial terminal hints.

## Scope For This Change

This implementation completed Phase 1 and is now executing the first part of Phase 2.

Out of scope for now:

- renaming internal socket paths;
- changing the wire protocol shape unless phase 1 proves insufficient;
- guaranteed tab-accurate routing inside JetBrains embedded terminals.

## Validation

Manual validation steps:

1. Launch Open Island.
2. Start Claude Code or Codex in:
   - Terminal
   - iTerm
   - PyCharm terminal
   - IntelliJ IDEA terminal
3. Click each corresponding island item.
4. Confirm:
   - Terminal and iTerm behavior remains unchanged.
   - JetBrains sessions bring the correct IDE to the foreground.
5. If a JetBrains jump still fails, inspect `/tmp/notch-monitor-jump.log` and verify the resolved bundle id and app name.
