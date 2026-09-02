#!/bin/bash
#
# Builds AiTwin.app from the Swift package.
#
# Swift Package Manager produces a bare Unix executable; macOS needs that
# executable wrapped in a bundle with an Info.plist before it can own a menu bar
# item, register as a login item, or be dragged to /Applications. This script
# does the wrapping. It needs only the Command Line Tools -- no Xcode.
#
#   ./Scripts/build-app.sh            # release build
#   ./Scripts/build-app.sh --debug    # faster build, slower app
#
set -euo pipefail

# Release is the default, and release builds do NOT contain the developer
# tools: the mood previews and the sample-data generator sit behind the
# AITWIN_DEV flag, which Package.swift sets only for debug configurations. So
# the app this produces is the one that can be handed to someone.
#
#   ./Scripts/build-app.sh          production  (no developer tools)
#   ./Scripts/build-app.sh --dev    development (Developer tab included)
CONFIG="release"
case "${1:-}" in
  --dev|--debug) CONFIG="debug" ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="AiTwin"
BUNDLE_ID="com.aitwin.companion"
VERSION="1.0.0"
BUILD="1"

BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP/Contents"

cd "$ROOT"

echo "==> Building ($CONFIG)…"
swift build -c "$CONFIG" --product "$APP_NAME"
BINARY="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"

if [[ ! -f "$BINARY" ]]; then
  echo "error: expected binary not found at $BINARY" >&2
  exit 1
fi

echo "==> Assembling $APP_NAME.app…"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BINARY" "$CONTENTS/MacOS/$APP_NAME"

# Character packs ship inside the bundle. User packs live in
# ~/Library/Application Support/AiTwin/Characters and take priority.
#
# Dotfiles are excluded, and that is not cosmetic: `.superseded/` holds frames
# moved aside during development rather than deleted, and a plain `cp -R` was
# copying them in. 24 MB of a 35 MB app -- and of the .dmg -- was dead art that
# the loader never reads, because it scans with .skipsHiddenFiles.
if [[ -d "$ROOT/Resources/Characters" ]]; then
  mkdir -p "$CONTENTS/Resources/Characters"
  rsync -a --exclude='.*' "$ROOT/Resources/Characters/" "$CONTENTS/Resources/Characters/"
fi

# Menu bar template image (the Ai_Twin mark).
if [[ -d "$ROOT/Resources/MenuBar" ]]; then
  cp -R "$ROOT/Resources/MenuBar" "$CONTENTS/Resources/MenuBar"
fi

# App icon, if one has been generated.
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
  ICON_ENTRY="<key>CFBundleIconFile</key><string>AppIcon</string>"
else
  ICON_ENTRY=""
fi

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  $ICON_ENTRY
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <!-- The key that makes AiTwin a menu bar app: no Dock icon, no app switcher
       entry. Without it the character would be accompanied by a bouncing Dock
       icon and a menu bar of its own, which is not a desktop companion. -->
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticTermination</key><false/>
  <key>NSSupportsSuddenTermination</key><false/>
  <key>NSHumanReadableCopyright</key><string>MIT Licensed</string>
</dict>
</plist>
PLIST

# An ad-hoc signature is enough to run locally and keeps macOS from complaining
# about a completely unsigned binary. It is NOT notarised -- see Docs/PACKAGING.md
# for what other people will see when they download it.
echo "==> Signing (ad-hoc)…"
codesign --force --deep --sign - "$APP" 2>/dev/null || echo "    (ad-hoc signing skipped)"

echo ""
if [[ "$CONFIG" == "debug" ]]; then
  echo "Built: $APP   [DEVELOPMENT — includes the Developer tab]"
else
  echo "Built: $APP   [production — developer tools not compiled in]"
fi
echo ""
echo "Run it:      open \"$APP\""
echo "Install it:  cp -R \"$APP\" /Applications/"
