#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP="build/ClaudeUsage.app"
ARCH="$(uname -m)"

# This repo may live on an ExFAT volume, which has no native extended
# attributes: macOS spills them into AppleDouble "._" sidecar files, and
# codesign refuses to sign a bundle containing them ("Operation not
# permitted / In subcomponent: ._MacOS"). So assemble and sign under TMPDIR
# (always on the internal APFS disk), then copy the finished bundle back.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
STAGE_APP="$STAGE/ClaudeUsage.app"

mkdir -p "$STAGE_APP/Contents/MacOS" "$STAGE_APP/Contents/Resources"

echo "Compiling ($ARCH)…"
swiftc -O -swift-version 5 \
  -target "${ARCH}-apple-macos13.0" \
  Sources/*.swift \
  -o "$STAGE_APP/Contents/MacOS/ClaudeUsage"

cp Info.plist "$STAGE_APP/Contents/Info.plist"

echo "Signing (ad-hoc)…"
codesign --force --deep --sign - "$STAGE_APP"

rm -rf build
mkdir -p build
ditto "$STAGE_APP" "$APP"

echo "Built $APP"
