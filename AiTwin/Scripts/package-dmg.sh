#!/bin/bash
#
# Wraps AiTwin.app in a .dmg for distribution.
#
#   ./Scripts/package-dmg.sh
#
# Produces build/AiTwin-<version>.dmg containing the app and a shortcut to
# /Applications, which is the drag-to-install layout Mac users expect.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="AiTwin"
VERSION="1.0.0"
APP="$ROOT/build/$APP_NAME.app"
DMG="$ROOT/build/$APP_NAME-$VERSION.dmg"
STAGING="$ROOT/build/dmg-staging"

if [[ ! -d "$APP" ]]; then
  echo "error: $APP not found. Run ./Scripts/build-app.sh first." >&2
  exit 1
fi

echo "==> Staging…"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "==> Creating disk image…"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING" \
  -ov -format UDZO \
  "$DMG" >/dev/null

rm -rf "$STAGING"

echo ""
echo "Built: $DMG"
echo ""
echo "NOTE: this disk image is ad-hoc signed and NOT notarised. Anyone who"
echo "downloads it will see a Gatekeeper warning and must right-click the app"
echo "and choose Open the first time. Notarisation needs a paid Apple Developer"
echo "account -- see Docs/PACKAGING.md."
