# Open Island 0.1.0

Initial public preview of Open Island.

Open Island is a macOS menu bar app for monitoring local Claude Code and Codex sessions with a lightweight notch-style panel. It surfaces session state, supported permission prompts, and jump-back actions so you can keep track of multiple local coding agents without living in terminal tabs all day.

## Included In This Preview

- live monitoring for local Claude Code and Codex sessions
- session states for active, waiting, completed, and error flows
- supported permission prompts surfaced in the panel
- jump-back behavior for Terminal, iTerm, and JetBrains-based IDEs
- local Unix socket bridge and launcher workflow

## Download

Asset:

- `Open-Island-0.1.0.dmg`

## Install Notes

This preview DMG is currently unsigned and not notarized.

To open it on macOS:

1. Download `Open-Island-0.1.0.dmg`.
2. Drag `Open Island.app` into `Applications`.
3. In Finder, open `Applications`.
4. Control-click `Open Island.app`.
5. Choose `Open`.

If macOS still blocks the app, go to:

- `System Settings -> Privacy & Security`

Then choose `Open Anyway`.

For jump and permission interactions, also enable:

- `System Settings -> Privacy & Security -> Accessibility`

## Known Limitations

- This is an early preview build.
- Terminal and iTerm jump behavior are currently stronger than JetBrains embedded terminal routing.
- JetBrains same-project multi-window jump accuracy is not yet consistently precise.
- The packaged DMG is unsigned and not notarized.

## Notes For Feedback

If you hit an issue, please include:

- macOS version
- whether you were using Terminal, iTerm, PyCharm, or IntelliJ IDEA
- which agent tool was running
- relevant excerpts from:
  - `/tmp/notch-monitor-jump.log`
  - `/tmp/notch-monitor-hook.log`
  - `/tmp/notch-monitor-codex-wrapper.log`

## Repo

- README: [README.md](../../README.md)
- unsigned install guide: [docs/unsigned-macos-install.md](../unsigned-macos-install.md)
- changelog: [CHANGELOG.md](../../CHANGELOG.md)
