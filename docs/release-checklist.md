# Open Island Release Checklist

## Pre-release

- Confirm the target version number.
- Update `README.md` if install or limitation notes changed.
- Update `CHANGELOG.md`.
- Build the app locally with `cd native/NotchMonitor && swift build`.
- Verify bridge scripts with:
  - `node --check bridge/server.js`
  - `node --check bridge/hook.js`
  - `node --check bridge/codex-wrapper.js`
- Run local smoke checks:
  - `open-island start`
  - verify panel renders
  - verify Claude Code session appears
  - verify Codex session appears
  - verify a permission prompt flow
  - verify terminal jump
- Rebuild the distributable DMG:
  - `bash scripts/package-dmg.sh <version>`

## Release packaging

- Confirm the DMG exists under `dist/`.
- Launch the packaged `.app` from the DMG on a clean macOS user session if possible.
- Verify first-run Accessibility onboarding.
- Verify the packaged app can bootstrap the bridge runtime.
- Confirm the app icon and display name are correct.

## Release notes

- Summarize user-visible changes.
- Call out known limitations, especially JetBrains routing limits.
- Mention that current DMG builds are unsigned unless notarization was added.

## Publish

- Create a Git tag for the release version.
- Create a GitHub Release.
- Upload the DMG.
- Paste the release notes.
- Link users to the unsigned install guide if the build is not signed.
