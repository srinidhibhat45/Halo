#!/bin/bash
# Publishes the files from Scripts/package-release.sh as a GitHub release (you run this; it is
# never run automatically). Needs the GitHub CLI, logged in: gh auth login
#
#   Scripts/publish-release.sh                 uses ../VERSION and ../docs/release-notes/<version>.md
#
# Pushing the tag also starts the Windows build on GitHub Actions, which adds HaloSetup.exe and
# the Windows update files to the same release.
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="$(tr -d '[:space:]' < ../VERSION)"
TAG="v${VERSION}"
NOTES="../docs/release-notes/${VERSION}.md"
REPO="srinidhibhat45/Halo"

[ -f "dist/Halo-${VERSION}-mac.dmg" ] || { echo "✗ Run Scripts/package-release.sh first." >&2; exit 1; }
[ -f "$NOTES" ] || { echo "✗ Write release notes in $NOTES first." >&2; exit 1; }

echo "This will publish Halo ${VERSION} (${TAG}) to github.com/${REPO} for everyone."
read -r -p "Continue? [y/N] " answer
[ "$answer" = "y" ] || [ "$answer" = "Y" ] || { echo "Cancelled."; exit 1; }

gh release create "$TAG" --repo "$REPO" --title "Halo ${VERSION}" --notes-file "$NOTES" dist/*
echo "✓ Published ${TAG}. Running copies of Halo will offer the update within a day."
