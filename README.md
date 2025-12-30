# IsMyMicOn

A tiny macOS menu bar utility to quickly see and switch audio input/output devices, with a live input level meter.

## Install

```sh
brew install --cask hackthehackerman/tap/ismymicon
```

Then launch `IsMyMicOn` from Applications (or Spotlight). The app lives in the menu bar.

## Running Locally

Requirements:

- macOS 11+
- Xcode
- XcodeGen (`brew install xcodegen`)

```sh
xcodegen generate
open IsMyMicOn.xcodeproj
```

Run the app from Xcode (Product > Run).

Build a runnable app bundle without signing:

```sh
./scripts/package.sh
open build/IsMyMicOn.app
```

## Usage

- Click the menu bar icon to see input/output devices and switch with one click.
- Grant microphone access to enable the live input level meter.
- Toggle "Show Virtual Devices" if you want to see virtual/aggregate audio devices.

## Credits

This project is 100% written by gpt-5.2-codex via codex cli.
