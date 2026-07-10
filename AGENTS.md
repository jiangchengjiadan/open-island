# Repository Guidelines

## Project Structure & Module Organization
This repository has three working areas:

- `native/NotchMonitor/`: Swift Package for the macOS menu bar app. Main sources live in `Sources/`, with UI in `Views/`, models in `Models/`, and socket logic in `Services/`.
- `bridge/`: Node.js Unix socket bridge. `server.js` runs the local socket server and `hook.js` registers agent sessions.
- `scripts/`: helper automation, currently `install-hooks.sh` for local hook setup.

Build artifacts already appear under `native/NotchMonitor/.build/` and `bridge/node_modules/`; treat them as generated output, not source.

## Build, Test, and Development Commands
- `cd bridge && npm install`: install bridge dependencies.
- `cd bridge && npm start`: run the socket bridge with Node.
- `cd bridge && npm run dev`: run the bridge with `nodemon` for local iteration.
- `cd native/NotchMonitor && swift build`: compile the Swift app.
- `cd native/NotchMonitor && swift run NotchMonitor`: launch the macOS app from source.
- `./scripts/install-hooks.sh`: install bridge dependencies and configure local hooks.

Run the bridge before launching the Swift app so `/tmp/notch-monitor.sock` is available.

## Coding Style & Naming Conventions
Follow existing file style instead of introducing new conventions:

- Swift uses 4-space indentation, `UpperCamelCase` for types, and `lowerCamelCase` for properties and methods.
- JavaScript in `bridge/` also uses 4-space indentation, semicolons, and CommonJS `require(...)`.
- Keep module names descriptive: `SocketService.swift`, `NotchPanel.swift`, `hook.js`.

No formatter or linter config is checked in, so keep edits small, consistent, and manually formatted.

## Testing Guidelines
There are no automated test targets in this snapshot. For changes:

- build the Swift app with `swift build`;
- start the bridge with `npm start`;
- verify agent registration and socket behavior manually.

If you add tests, place Swift tests under `native/NotchMonitor/Tests/` and JavaScript tests under `bridge/tests/`.

## Open Island Implementation Notes
- Runtime bridge scripts exist in two places: `bridge/` for source development and `native/NotchMonitor/Sources/AppRuntime/bridge/` for packaged app runtime. Keep matching behavior in sync when editing `server.js`, `hook.js`, or `codex-wrapper.js`.
- Permission approval behavior spans Swift UI, `SocketService.swift`, `bridge/server.js`, and `bridge/hook.js`; update the full path together so the island display, socket protocol, and agent hook output remain consistent.
- The notch panel window height is calculated both in SwiftUI (`NotchPanelView`) and AppKit (`NotchPanelWindow`). When adding visible row content such as approval bars or prompt controls, update both height calculations so controls are not clipped.
- For permission auto-approval features, prefer conservative session-scoped matching in the bridge layer. Avoid broad command-family approval unless the rule is explicit and low risk.

## Commit & Pull Request Guidelines
Git history is not available in this workspace snapshot, so use a simple conventional pattern: imperative, scoped commit subjects such as `bridge: handle stale socket cleanup` or `native: refine panel hover behavior`.

Pull requests should include a short summary, manual verification steps, linked issue or task context, and screenshots or recordings for any UI change in the notch panel.
