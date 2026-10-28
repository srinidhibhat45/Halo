# Halo — build without Xcode (Command Line Tools + SwiftPM).
.PHONY: build app run install uninstall reset-permissions test clean icon release publish

APP := build/Halo.app
INSTALL_DIR := $(HOME)/Applications

## Compile only (debug).
build:
	swift build

## Release app bundle at build/Halo.app.
app:
	Scripts/build-app.sh

## Build and launch (quits a running copy first).
run: app
	-osascript -e 'tell application id "com.srinidhibhat.Halo" to quit' 2>/dev/null
	open "$(APP)"

## Copy to ~/Applications (a stable path keeps macOS permissions attached) and launch.
install: app
	-osascript -e 'tell application id "com.srinidhibhat.Halo" to quit' 2>/dev/null
	mkdir -p "$(INSTALL_DIR)"
	rm -rf "$(INSTALL_DIR)/Halo.app"
	cp -R "$(APP)" "$(INSTALL_DIR)/Halo.app"
	open "$(INSTALL_DIR)/Halo.app"

## After a rebuild, macOS keeps a stale Accessibility/Automation entry for the old build.
## This clears Halo's entries (only Halo's) so it can ask again cleanly.
reset-permissions:
	-tccutil reset Accessibility com.srinidhibhat.Halo
	-tccutil reset AppleEvents com.srinidhibhat.Halo

uninstall:
	-osascript -e 'tell application id "com.srinidhibhat.Halo" to quit' 2>/dev/null
	rm -rf "$(INSTALL_DIR)/Halo.app"

## Release files (universal DMG + update zip + checksums) in dist/.
release:
	Scripts/package-release.sh

## Publish dist/ as a GitHub release (asks for confirmation).
publish:
	Scripts/publish-release.sh

## Unit tests (HaloCore).
test:
	Scripts/test.sh

## Regenerate the app icon only.
icon:
	rm -rf build/AppIcon.iconset build/AppIcon.icns
	swift Scripts/make-icon.swift build/AppIcon.iconset
	iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns

clean:
	rm -rf .build build dist
