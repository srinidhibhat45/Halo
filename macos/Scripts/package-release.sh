#!/bin/bash
# Packages a Halo release for macOS into dist/:
#   Halo-<version>-mac.dmg          installer (drag Halo to Applications)
#   Halo-<version>-mac.zip          update payload used by Halo's built-in updater
#   Halo-<version>-mac.zip.sha256   its checksum (the updater refuses anything that doesn't match)
#
#   Scripts/package-release.sh            uses the version in ../VERSION (repository root)
# Publishing is a separate, deliberate step: Scripts/publish-release.sh.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/../VERSION")"
DIST="$ROOT/dist"
NAME="Halo-${VERSION}-mac"

UNIVERSAL="${UNIVERSAL:-1}" CONFIG=release "$ROOT/Scripts/build-app.sh"
APP="$ROOT/build/Halo.app"

rm -rf "$DIST" && mkdir -p "$DIST"

echo "▸ Update archive…"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/${NAME}.zip"
(cd "$DIST" && shasum -a 256 "${NAME}.zip" > "${NAME}.zip.sha256")

echo "▸ Disk image…"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/Halo.app"
ln -s /Applications "$STAGING/Applications"
cat > "$STAGING/Read Me First.txt" <<TXT
Install Halo
1. Drag Halo onto the Applications folder.
2. Open Halo from Applications.

If macOS says Halo "can't be opened" or "can't be verified":
Halo is free and open source but not notarised by Apple. Open System Settings ›
Privacy & Security, scroll down and click "Open Anyway" next to Halo. You only do
this once; later updates install themselves from inside Halo.

More help: https://github.com/srinidhibhat45/Halo#readme
TXT
hdiutil create -volname "Halo ${VERSION}" -srcfolder "$STAGING" -ov -format UDZO -fs HFS+ "$DIST/${NAME}.dmg" >/dev/null
(cd "$DIST" && shasum -a 256 "${NAME}.dmg" > "${NAME}.dmg.sha256")

echo "✓ Release files in $DIST:"
ls -lh "$DIST" | awk 'NR>1 {print "   " $9 "  " $5}'
