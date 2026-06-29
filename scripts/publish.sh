#!/usr/bin/env bash
#
# Publishes Sweep to GitHub: creates/updates the repo (description, topics,
# website), enables GitHub Pages (served from /docs), builds a DMG and attaches
# it to a release. The DMG is built fresh here and is NOT committed.
#
# This script is NOT run automatically. Review it, log in (`gh auth login`),
# then run it yourself:  ./scripts/publish.sh
#
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="Alyetama/Sweep"
VERSION="v1.0.0"
DESCRIPTION="A native macOS app uninstaller that finds every file an app leaves behind — and cleans up leftovers from apps you've already deleted."
HOMEPAGE="https://alyetama.github.io/Sweep/"
DMG="Sweep.dmg"

command -v gh >/dev/null || { echo "✗ GitHub CLI (gh) not found — install it first."; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "✗ Not logged in. Run: gh auth login"; exit 1; }

# 1. Create the repo on first run (no-op if it exists), pushing main.
if ! gh repo view "$REPO" >/dev/null 2>&1; then
	echo "▸ Creating $REPO …"
	gh repo create "$REPO" --public --source=. --remote=origin --push --description "$DESCRIPTION"
else
	echo "▸ Repo exists — pushing main …"
	git remote get-url origin >/dev/null 2>&1 || git remote add origin "https://github.com/$REPO.git"
	git push -u origin main
fi

# 2. Description, website, and topics (shown on the GitHub repo page).
echo "▸ Setting description, website, and topics …"
gh repo edit "$REPO" \
	--description "$DESCRIPTION" \
	--homepage "$HOMEPAGE" \
	--add-topic macos \
	--add-topic macos-app \
	--add-topic swift \
	--add-topic swiftui \
	--add-topic uninstaller \
	--add-topic app-uninstaller \
	--add-topic app-cleaner \
	--add-topic mac-cleaner \
	--add-topic cleanmymac \
	--add-topic appcleaner \
	--add-topic utility \
	--add-topic native-macos

# 3. Enable GitHub Pages, served from /docs on main.
echo "▸ Enabling GitHub Pages (main /docs) …"
gh api -X POST "repos/$REPO/pages" \
	-f "source[branch]=main" -f "source[path]=/docs" 2>/dev/null \
	|| gh api -X PUT "repos/$REPO/pages" \
		-f "source[branch]=main" -f "source[path]=/docs" 2>/dev/null || true
echo "  Pages: $HOMEPAGE"

# 4. Build the app and package a drag-to-Applications DMG.
echo "▸ Building release …"
./build.sh release
echo "▸ Building $DMG …"
STAGING="$(mktemp -d)"
cp -R Sweep.app "$STAGING/Sweep.app"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "Sweep" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"
echo "  → $DMG ($(du -h "$DMG" | cut -f1))"

# 5. Cut a release with the DMG. (The Pages "Download" button points at
#    releases/latest/download/Sweep.dmg, so keep this asset name.)
NOTES_FILE="$(mktemp)"
cat > "$NOTES_FILE" <<'NOTES'
A native macOS app uninstaller that finds every file an app leaves behind —
caches, preferences, containers, logs and more — shows them pre-selected, and
asks before moving them to the Trash. Plus a Leftovers scanner for orphaned files
from apps you've already deleted.

### Install
Open `Sweep.dmg` and drag **Sweep** into your **Applications** folder.

### Opening it the first time
Sweep is open-source and ad-hoc signed (no paid Apple Developer ID), so macOS
Gatekeeper blocks it on first launch. Do one of these once:

**Terminal (quickest)**
```
xattr -dr com.apple.quarantine /Applications/Sweep.app
```
then open it normally.

**System Settings**
1. Double-click Sweep, then click **Done** on the warning.
2. **System Settings → Privacy & Security**.
3. Click **Open Anyway** next to the "Sweep was blocked" message, then **Open**.
NOTES

echo "▸ Creating release $VERSION …"
gh release create "$VERSION" "$DMG" \
	--repo "$REPO" \
	--title "Sweep ${VERSION#v}" \
	--notes-file "$NOTES_FILE"
rm -f "$NOTES_FILE"

echo "✓ Published."
echo "  Release:  https://github.com/$REPO/releases/tag/$VERSION"
echo "  Download: https://github.com/$REPO/releases/latest/download/$DMG"
echo "  Website:  $HOMEPAGE"
