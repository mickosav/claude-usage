#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# Build, then replace the installed copy and relaunch. Run after code changes.
./build.sh

APP="build/ClaudeUsage.app"
DEST="/Applications/ClaudeUsage.app"

echo "Stopping running instance…"
osascript -e 'quit app "ClaudeUsage"' 2>/dev/null || true
sleep 1
pkill -f "ClaudeUsage.app" 2>/dev/null || true
sleep 1

echo "Installing to ${DEST}…"
rm -rf "$DEST"
cp -R "$APP" "$DEST"
# If build/ sits on ExFAT its "._" AppleDouble files come along as real files
# and codesign rejects the bundle. dot_clean folds them back into xattrs.
dot_clean -m "$DEST" 2>/dev/null || true
codesign --force --deep --sign - "$DEST"

echo "Launching…"
open "$DEST"
echo "Done."
