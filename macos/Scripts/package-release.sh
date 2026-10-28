#!/bin/bash
# Packages a Halo release for macOS into dist/:
#   Halo-mac.dmg                    installer (drag Halo to Applications); the name has no version
#                                   so releases/latest/download/Halo-mac.dmg always works
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
# What these files were built from; publish-release.sh refuses to publish anything else.
echo "${VERSION} $(git rev-parse HEAD)$([ -z "$(git status --porcelain -- "$ROOT" "$ROOT/../VERSION")" ] || echo '-modified')" > "$DIST/.built-from"

echo "▸ Update archive…"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/${NAME}.zip"
(cd "$DIST" && shasum -a 256 "${NAME}.zip" > "${NAME}.zip.sha256")

echo "▸ Disk image…"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/Halo.app"
ln -s /Applications "$STAGING/Applications"
cat > "$STAGING/Read Me First.txt" <<TXT
Install Halo ${VERSION}
1. Drag Halo onto the Applications folder.
2. Open Halo from your Applications folder (not from this window).

The first time, macOS may say "Halo" Not Opened / Apple could not verify it.
Halo is free and open source but isn't notarised by Apple, so macOS asks you once:
  1. Click Done.
  2. Open System Settings > Privacy & Security and scroll down to Security.
  3. Click "Open Anyway" next to Halo, enter your password and click Open Anyway again.
Later updates install themselves from inside Halo, without this step.

Then Halo's welcome guide asks for Accessibility, which it needs to press keys,
control media and move windows. Press Control-Shift-Command-H to open the ring.

Help: https://github.com/srinidhibhat45/Halo#readme
TXT
hdiutil create -volname "Halo ${VERSION}" -srcfolder "$STAGING" -ov -format UDZO -fs HFS+ "$DIST/Halo-mac.dmg" >/dev/null
(cd "$DIST" && shasum -a 256 "Halo-mac.dmg" > "Halo-mac.dmg.sha256")

echo "✓ Release files in $DIST:"
ls -lh "$DIST" | awk 'NR>1 {print "   " $9 "  " $5}'
