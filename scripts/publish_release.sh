#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-}"
ZIP_PATH="${2:-build/IsMyMicOn.zip}"

if [[ -z "$VERSION" ]]; then
  echo "Usage: $0 <version> [zip_path]"
  exit 1
fi

if [[ ! -f "$ZIP_PATH" ]]; then
  echo "Release zip not found at: $ZIP_PATH"
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI (gh) is required: https://cli.github.com/"
  exit 1
fi

TAG="v$VERSION"

if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "Tag already exists: $TAG"
  exit 1
fi

SHA=$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')
echo "SHA256: $SHA"

git tag "$TAG"
git push origin "$TAG"

gh release create "$TAG" "$ZIP_PATH" --title "IsMyMicOn v$VERSION" --generate-notes
