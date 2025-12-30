#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="IsMyMicOn"
BUILD_DIR="$ROOT_DIR/build"
DERIVED_DATA="$BUILD_DIR/DerivedData"
STAGING_APP="$BUILD_DIR/${APP_NAME}.app"
ZIP_PATH="$BUILD_DIR/${APP_NAME}.zip"
NOTARY_ZIP="$BUILD_DIR/${APP_NAME}-notary.zip"

CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

xcodebuild \
  -project "$ROOT_DIR/IsMyMicOn.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO

APP_PATH="$DERIVED_DATA/Build/Products/Release/${APP_NAME}.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found at $APP_PATH"
  exit 1
fi

rm -rf "$STAGING_APP"
ditto "$APP_PATH" "$STAGING_APP"

if [[ -n "$NOTARY_PROFILE" && -z "$CODESIGN_IDENTITY" ]]; then
  echo "NOTARY_PROFILE is set, but CODESIGN_IDENTITY is empty."
  exit 1
fi

if [[ -n "$CODESIGN_IDENTITY" ]]; then
  codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$STAGING_APP"
  codesign --verify --strict "$STAGING_APP"
fi

if [[ -n "$NOTARY_PROFILE" ]]; then
  rm -f "$NOTARY_ZIP"
  ditto -c -k --sequesterRsrc --keepParent "$STAGING_APP" "$NOTARY_ZIP"
  xcrun notarytool submit "$NOTARY_ZIP" --wait --keychain-profile "$NOTARY_PROFILE"
  xcrun stapler staple "$STAGING_APP"
fi

rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$STAGING_APP" "$ZIP_PATH"
shasum -a 256 "$ZIP_PATH"
echo "Created $ZIP_PATH"
