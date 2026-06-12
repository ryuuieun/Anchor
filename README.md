# Anchor

Anchor is a small macOS menu bar app for switching back to specific windows.
Bind the currently focused window to a numbered slot from the menu, then use the
slot hotkey to focus that exact window later.

## Requirements

- macOS 13 or later
- Accessibility permission for Anchor
- No App Sandbox or App Store distribution assumptions

## How It Works

- Window capture and focus use macOS Accessibility APIs (`AXUIElement`).
- App activation uses `NSWorkspace` / `NSRunningApplication`.
- Global hotkeys use Carbon `RegisterEventHotKey` behind a small registrar
  adapter.
- Bindings are runtime-only. Restarting Anchor clears window slots.

## Build

```sh
swift test
./script/build_and_run.sh --init-signing
./script/build_and_run.sh --build-only
```

Run locally:

```sh
./script/build_and_run.sh
```

Install to `/Applications`:

```sh
./script/build_and_run.sh --install
```

## Limits

Anchor manages real top-level macOS windows, not browser tabs, editor tabs,
Spaces, Mission Control, or layouts. Full-screen and cross-Space behavior
depends on macOS and the target app's Accessibility support.
