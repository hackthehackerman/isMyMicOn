# Architecture

## Project Goal
- Build a lightweight macOS menu bar utility that shows active audio input/output devices, lists available devices, and lets the user switch with one click.
- Provide a live input level meter (like System Settings) to verify the mic is working.
- Keep the app simple, reliable, and installable via Homebrew (open source, unsigned is acceptable for MVP).

## Key Decisions
- UI framework: AppKit with `NSStatusItem` for maximum control and compatibility.
- Minimum macOS: 11 (Big Sur) to cover Apple Silicon devices broadly.
- Status bar UI: compact indicator (icon + short text). Live input meter runs only when the menu is open.
- Input meter: enabled on-demand to avoid keeping the mic indicator active all the time.
- Output level: show system output volume (0-100%) rather than live output signal level (MVP).
- Permission UX: show "Mic access required" as a menu item until the user grants permission.

## Architecture Overview
The app is a single-process menu bar application with four primary subsystems:

1) **Audio Device Manager**
   - Enumerates input/output devices.
   - Reads the current default input/output device.
   - Switches defaults when the user selects a device.

2) **Input Meter**
   - Captures live input levels from the current input device.
   - Runs at ~15-20 Hz only while the menu is open.
   - Exposes a normalized level (0.0 - 1.0) for UI rendering.

3) **Menu Bar UI**
   - Status item with compact label (device abbreviation or short name).
   - Dropdown menu with two sections:
     - Input Devices (checkmark on active device, click to switch)
     - Output Devices (checkmark on active device, click to switch)
   - Input meter shown inside the menu (not always in the status item).
   - Output volume displayed as a percentage in the menu.

4) **Permission Handling**
   - Detects whether mic access has been granted.
   - If not granted, shows "Mic access required" menu item and disables the meter.
   - When granted, meter activates only while menu is open.

## Packaging and Distribution
- Build as a macOS app bundle, unsigned for MVP.
- Distribute via Homebrew cask.
- Users will need to approve the app on first run (Gatekeeper).

## Non-Goals (MVP)
- No per-app routing or advanced audio session management.
- No global hotkeys.
- No live output signal metering.
- No custom installer; Homebrew cask only.

## Idea Bank
- Optional status item meter (toggle).
- Launch at login.
- Hotkey to toggle input/output quickly.
- Persistent device preference profiles for conferencing apps.
