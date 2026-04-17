# Installing The Unsigned Open Island DMG

Current DMG builds are unsigned and not notarized. That is acceptable for developer preview distribution, but macOS will warn before first launch.

## Recommended path

1. Download `Open-Island-<version>.dmg`.
2. Open the DMG and drag `Open Island.app` into `Applications`.
3. In Finder, open `Applications`.
4. Control-click `Open Island.app`.
5. Choose `Open`.
6. Confirm the macOS warning dialog.

After the first successful open, you can launch the app normally.

## If macOS still blocks the app

Go to:

- `System Settings -> Privacy & Security`

Look for the blocked app message near the bottom of the page, then choose `Open Anyway`.

## Accessibility permission

For jump and approval behavior, also enable:

- `System Settings -> Privacy & Security -> Accessibility`

Allow the terminal or app you used to start Open Island.

## Distribution note

For broader public distribution outside a developer-preview audience, add Developer ID signing and Apple notarization.
