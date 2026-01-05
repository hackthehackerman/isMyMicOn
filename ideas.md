# Ideas

## Auto-Switch Rules

Auto-switch input/output based on app lifecycle (Zoom/Teams/Meet/etc.), with per-app rules:
- On app launch: set input/output to chosen devices.
- On app quit: restore previous devices.
- Optional delay to avoid race conditions when the app starts.

## Login Item

Launch at login toggle in the menu:
- Uses `SMAppService` for modern macOS.
- Simple on/off state, no UI beyond the menu.

## Menu Bar Modes

Multiple menu bar display modes:
- Icon only.
- Icon + two-line `In/Out` text (current).
- Icon + short single-line summary (space saving).

## Input Test

Quick mic test controls:
- Live input meter with a short peak hold.
- Optional “Play test tone” output button (future).
