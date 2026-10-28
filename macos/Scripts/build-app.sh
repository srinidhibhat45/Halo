#!/bin/bash
# Builds Halo.app from the Swift package, without Xcode.
#
#   Scripts/build-app.sh            release build → build/Halo.app
#   CONFIG=debug Scripts/build-app.sh
#
# Signing: ad hoc by default. macOS ties privacy permissions (Accessibility, Automation) to the
# signature, and an ad-hoc signature changes with every build, so after a rebuild you may need to
# switch Halo off and on again in System Settings › Privacy & Security (or run
# `make reset-permissions` and grant again). If you have a code-signing certificate, building with
# it keeps permissions across rebuilds:
#   SIGN_IDENTITY="Your Certificate Name" Scripts/build-app.sh
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
CONFIG="${CONFIG:-release}"
VERSION="$(tr -d '[:space:]' < "$ROOT/../VERSION" 2>/dev/null || echo 1.0.0)"
BUILD_NUMBER="$(date +%Y%m%d%H%M)"
OUT="$ROOT/build/Halo.app"
ICONSET="$ROOT/build/AppIcon.iconset"
ICNS="$ROOT/build/AppIcon.icns"

# UNIVERSAL=1 builds for Apple silicon and Intel (used for releases).
# (macOS's bash 3.2 treats an empty array as unbound under `set -u`, hence the ${…+…} form.)
ARCH_FLAGS=()
ARCH_LABEL=""
if [ "${UNIVERSAL:-0}" = "1" ]; then ARCH_FLAGS=(--arch arm64 --arch x86_64); ARCH_LABEL=", universal"; fi

echo "▸ Compiling (${CONFIG}${ARCH_LABEL})…"
swift build -c "$CONFIG" --product Halo ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} 2>&1 | grep -vE "ld: warning: search path|^\[[0-9]+ ?/ ?[0-9]+\]" || true
BIN_DIR="$(swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"
if [ ! -x "$BIN_DIR/Halo" ]; then
    echo "✗ Build failed: $BIN_DIR/Halo not found" >&2
    exit 1
fi

echo "▸ Icon…"
if [ ! -f "$ICNS" ] || [ "$ROOT/Scripts/make-icon.swift" -nt "$ICNS" ]; then
    rm -rf "$ICONSET"
    swift "$ROOT/Scripts/make-icon.swift" "$ICONSET"
    iconutil -c icns "$ICONSET" -o "$ICNS"
fi

echo "▸ Assembling ${OUT}…"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp "$BIN_DIR/Halo" "$OUT/Contents/MacOS/Halo"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" "$ROOT/Resources/Info.plist" > "$OUT/Contents/Info.plist"
plutil -lint -s "$OUT/Contents/Info.plist"
printf 'APPL????' > "$OUT/Contents/PkgInfo"
cp "$ICNS" "$OUT/Contents/Resources/AppIcon.icns"

SIGN_IDENTITY="${SIGN_IDENTITY:--}"
if [ "$SIGN_IDENTITY" = "-" ]; then echo "▸ Signing (ad hoc)…"; else echo "▸ Signing with \"$SIGN_IDENTITY\"…"; fi
# Ad-hoc signatures normally identify the build by its hash, so every rebuild or update looks like
# a new app to macOS privacy settings and loses Accessibility. A designated requirement naming
# the bundle identifier keeps the grant valid across builds.
REQUIREMENT=()
if [ "$SIGN_IDENTITY" = "-" ]; then REQUIREMENT=(--requirements '=designated => identifier "com.srinidhibhat.Halo"'); fi
codesign --force --sign "$SIGN_IDENTITY" ${REQUIREMENT[@]+"${REQUIREMENT[@]}"} --timestamp=none "$OUT"
codesign --verify --strict "$OUT"

echo "✓ Built ${OUT} (${VERSION}, build ${BUILD_NUMBER})"
