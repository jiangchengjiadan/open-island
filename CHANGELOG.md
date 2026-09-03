# Changelog

All notable changes to this project will be documented in this file.

## Unreleased

- Pair Codex processes to sessions by stable keys instead of array index.
- Limit onboarding nags to tools that are actually configured or installed.
- Treat Accessibility as recommended instead of a required setup blocker.
- Fetch usage from the network only while the Usage tab is visible.
- Restart the local bridge after unexpected crashes, with backoff and a retry cap (PR 7).
- Make open-island start and stop a daily-driver workflow, including leftover bridge cleanup (PR 8 and 9).
- Use the public npmjs registry for CI and local installs.
- Align package-dmg.sh default version with the current 0.2.0 product version.
- Improve session routing so same-name sessions stay distinct across tty, pid, and cwd.
- Keep hook installation transactional and verify bundled runtime files with a manifest.

## 0.2.0

- Added default Codex hook installation and updated hook compatibility for current Codex CLI behavior.
- Added Qoder hook installation, session monitoring, and first-pass permission compatibility.
- Hardened bridge behavior with stale session cleanup, permission request queueing, and limited bootstrap self-heal.
- Improved Codex session de-duplication to better avoid rendering auxiliary processes as separate sessions.
- Expanded jump behavior with first-pass Ghostty and Warp support.
- Reworked iTerm/tmux jump toward session-first targeting and improved multi-window return accuracy.
- Added workspace-level jump for VS Code and Cursor via editor CLI reopening.
- Refreshed English and Chinese README content to match the current capability set.
- Added gap analysis, backlog planning, open-vibe-island reference notes, and manual M1 test cases.

## 0.1.0

- Initial public preview of Open Island.
- macOS menu bar app for monitoring local Claude Code and Codex sessions.
- Local Unix socket bridge, permission surfacing, and terminal jump support.
