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

[ -f "dist/Halo-mac.dmg" ] && [ -f "dist/Halo-${VERSION}-mac.zip" ] || { echo "✗ Run make release first." >&2; exit 1; }
[ -f "$NOTES" ] || { echo "✗ Write release notes in $NOTES first." >&2; exit 1; }

# The release must be exactly the pushed commit the files were built from.
COMMIT="$(git rev-parse HEAD)"
[ -z "$(git status --porcelain -- . ../VERSION ../windows ../docs)" ] || { echo "✗ There are uncommitted changes. Commit and push them, then run make release again." >&2; exit 1; }
git fetch -q origin main
[ "$(git rev-parse origin/main)" = "$COMMIT" ] || { echo "✗ This commit isn't what's on GitHub (origin/main). Push it (or pull), then run make release again." >&2; exit 1; }
[ "$(cat dist/.built-from 2>/dev/null)" = "${VERSION} ${COMMIT}" ] || { echo "✗ The files in dist/ weren't built from this commit. Run make release again." >&2; exit 1; }
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then echo "✗ ${TAG} is already published. Raise the version in VERSION first." >&2; exit 1; fi

echo "This will publish Halo ${VERSION} (${TAG}) to github.com/${REPO} for everyone."
read -r -p "Continue? [y/N] " answer
[ "$answer" = "y" ] || [ "$answer" = "Y" ] || { echo "Cancelled."; exit 1; }

gh release create "$TAG" --repo "$REPO" --target "$COMMIT" --title "Halo ${VERSION}" --notes-file "$NOTES" --latest dist/*
echo "✓ Published ${TAG}: https://github.com/${REPO}/releases/tag/${TAG}"
echo "  The Windows installer is being built on GitHub Actions and appears on that page in about"
echo "  10 minutes: https://github.com/${REPO}/actions/workflows/release-windows.yml"
echo "  Running copies of Halo offer the update within a day."
