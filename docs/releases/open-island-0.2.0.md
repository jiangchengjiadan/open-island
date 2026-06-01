# Open Island 0.2.0

Second public preview of Open Island.

Open Island is a macOS menu bar app for monitoring local coding-agent sessions with a notch-style panel. `0.2.0` focuses on making the local workflow materially more usable: stronger hook installation, more stable permission handling, broader jump coverage, and better return accuracy for common terminal and editor setups.

## Included In This Preview

- live monitoring for local Claude Code, Codex, and Qoder CLI sessions
- default Codex hook installation and updated Codex hook compatibility
- supported permission prompts surfaced in the panel
- bridge-side stale session cleanup and permission-request queueing
- jump-back behavior for Terminal, iTerm, Ghostty, Warp, VS Code, Cursor, and JetBrains-based IDEs
- improved iTerm/tmux session-first jump behavior
- workspace-level reopen flow for VS Code and Cursor

## Download

Asset:

- `Open-Island-0.2.0.dmg`

## Install Notes

This preview DMG is currently unsigned and not notarized.

To open it on macOS:

1. Download `Open-Island-0.2.0.dmg`.
2. Drag `Open Island.app` into `Applications`.
3. In Finder, open `Applications`.
4. Control-click `Open Island.app`.
5. Choose `Open`.

If macOS still blocks the app, go to:

- `System Settings -> Privacy & Security`

Then choose `Open Anyway`.

For jump and permission interactions, also enable:

- `System Settings -> Privacy & Security -> Accessibility`

## Notable Changes Since 0.1.0

- Codex hooks now install by default.
- Qoder monitoring and hook installation were added.
- Permission handling is more stable under concurrent requests.
- Stale sessions are cleaned up automatically.
- iTerm multi-window return behavior improved.
- VS Code and Cursor can reopen the owning workspace directly.
- Ghostty and Warp now have first-pass jump support.

## Known Limitations

- This is still an early preview build.
- JetBrains same-project multi-window jump accuracy is not yet consistently precise.
- Ghostty and Warp jump are still best-effort first versions.
- The packaged DMG is unsigned and not notarized.

## Notes For Feedback

If you hit an issue, please include:

- macOS version
- whether you were using Terminal, iTerm, VS Code, Cursor, PyCharm, or another supported host
- which agent tool was running
- relevant excerpts from:
  - `/tmp/notch-monitor-jump.log`
  - `/tmp/notch-monitor-hook.log`
  - `/tmp/notch-monitor-codex-wrapper.log`

## Repo

- README: [README.md](../../README.md)
- unsigned install guide: [docs/unsigned-macos-install.md](../unsigned-macos-install.md)
- changelog: [CHANGELOG.md](../../CHANGELOG.md)
