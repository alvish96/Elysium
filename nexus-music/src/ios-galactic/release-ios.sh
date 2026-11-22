#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: ./release-ios.sh <version> [release notes]"
  echo "Example: ./release-ios.sh 2.2.0 \"Amperfy playlist links, closable player bar, Spotify single-track downloads\""
  exit 1
fi

VERSION="$1"
NOTES="${2:-Nexus Music Galactic v${VERSION} update}"
TAG="v${VERSION}"
BUILD_NUM="$(date +%Y%m%d%H%M)"
RELEASE_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

IOS_DIR="$HOME/Documents/Elysium/nexus-music/src/ios-galactic"
ELYSIUM_DIR="$HOME/Documents/Elysium"
RELEASE_REPO="alvish96/nexus-music-releases"
RELEASE_DIR="$HOME/Documents/nexus-music-releases"

cd "$IOS_DIR"

echo "==> [1/5] Generating Xcode project & compiling Release build (${VERSION})..."
xcodegen generate
rm -rf build
xcodebuild -project NexusMusicGalactic.xcodeproj \
           -scheme NexusMusicGalactic \
           -configuration Release \
           -sdk iphoneos \
           -derivedDataPath build \
           MARKETING_VERSION="$VERSION" \
           CURRENT_PROJECT_VERSION="$BUILD_NUM" \
           CODE_SIGNING_ALLOWED=NO \
           CODE_SIGNING_REQUIRED=NO \
           CODE_SIGN_IDENTITY="" \
           | tail -n 20

APP_PATH="build/Build/Products/Release-iphoneos/NexusMusicGalactic.app"
if [ ! -d "$APP_PATH" ]; then
  echo "ERROR: Build failed — $APP_PATH not found."
  exit 1
fi

echo "==> [2/5] Stamping version metadata & packaging NexusMusicGalactic.ipa..."
mkdir -p build/Payload
cp -R "$APP_PATH" build/Payload/
PLIST="build/Payload/NexusMusicGalactic.app/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUM" "$PLIST"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$PLIST")"

IPA_NAME="NexusMusicGalactic-v${VERSION}.ipa"
IPA_PATH="$IOS_DIR/build/${IPA_NAME}"
(cd build && zip -qr "$IPA_PATH" Payload)
IPA_SIZE="$(stat -f%z "$IPA_PATH")"
echo "    Bundle ID: $BUNDLE_ID | Size: $IPA_SIZE bytes"

echo "==> [3/5] Publishing GitHub Release ${TAG} to ${RELEASE_REPO}..."
if gh release view "$TAG" --repo "$RELEASE_REPO" >/dev/null 2>&1; then
  gh release upload "$TAG" "$IPA_PATH" --repo "$RELEASE_REPO" --clobber
  gh release edit "$TAG" --repo "$RELEASE_REPO" --title "Nexus Music Galactic ${TAG}" --notes "$NOTES"
else
  gh release create "$TAG" "$IPA_PATH" \
    --repo "$RELEASE_REPO" \
    --title "Nexus Music Galactic ${TAG}" \
    --notes "$NOTES"
fi

DOWNLOAD_URL="https://github.com/${RELEASE_REPO}/releases/download/${TAG}/${IPA_NAME}"
ICON_URL="https://raw.githubusercontent.com/${RELEASE_REPO}/main/icon.png"

echo "==> [4/5] Updating SideStore / AltStore source.json feed..."
cd "$RELEASE_DIR"
git pull --rebase origin main
cp "$IOS_DIR/Sources/Assets.xcassets/AppIcon.appiconset/AppIcon.png" ./icon.png

python3 - "$VERSION" "$RELEASE_DATE" "$IPA_SIZE" "$DOWNLOAD_URL" "$NOTES" "$BUNDLE_ID" "$ICON_URL" << 'PYEOF'
import json, os, sys

version, rel_date, size_s, dl_url, notes, bundle_id, icon_url = sys.argv[1:8]
size = int(size_s)
path = "source.json"

if os.path.exists(path):
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
else:
    data = {}

old_versions = []
if data.get("apps") and isinstance(data["apps"], list) and data["apps"][0].get("versions"):
    old_versions = [v for v in data["apps"][0]["versions"] if v.get("version") != version]

new_entry = {
    "version": version,
    "date": rel_date,
    "localizedDescription": notes,
    "downloadURL": dl_url,
    "size": size,
    "minOSVersion": "17.0"
}

all_versions = [new_entry] + old_versions

feed = {
    "name": "Nexus Music Galactic",
    "subtitle": "Imperial Audio Sync & Archive Companion",
    "description": "Official release feed for Nexus Music Galactic iOS builds. Add once in SideStore or AltStore for 1-tap updates.",
    "iconURL": icon_url,
    "website": "https://github.com/alvish96/nexus-music-releases",
    "tintColor": "#10b981",
    "featuredApps": [bundle_id],
    "apps": [
        {
            "name": "Nexus Music",
            "bundleIdentifier": bundle_id,
            "developerName": "alvish96",
            "subtitle": "Universal Spotify/YouTube Sync & Audio Deck",
            "localizedDescription": "Native iOS companion for Nexus Music on Atlantis. Sync Spotify playlists, download individual Spotify/YouTube tracks at 320kbps, track live per-song telemetry, and jump straight into Amperfy.",
            "iconURL": icon_url,
            "tintColor": "#10b981",
            "category": "entertainment",
            "versions": all_versions,
            "appPermissions": {
                "entitlements": [],
                "privacy": {}
            }
        }
    ]
}

with open(path, "w", encoding="utf-8") as f:
    json.dump(feed, f, indent=2)
    f.write("\n")
PYEOF

git add source.json icon.png
git commit -m "release(ios): publish Nexus Music Galactic ${TAG}"
git push origin main

echo "==> [5/5] Cleaning build cache & tagging private Elysium source..."
rm -rf "$IOS_DIR/build"
cd "$ELYSIUM_DIR"
git add nexus-music/src/ios-galactic/release-ios.sh
git diff --cached --quiet || git commit -m "chore(ios): add automated GitHub Release and SideStore feed script"
git tag -fa "ios-${TAG}" -m "iOS Release ${TAG}: ${NOTES}"
git push origin main
git push origin "ios-${TAG}" --force

echo ""
echo "============================================================"
echo "RELEASE COMPLETE: Nexus Music Galactic ${TAG}"
echo "Direct .ipa:     ${DOWNLOAD_URL}"
echo "SideStore Feed:  https://raw.githubusercontent.com/${RELEASE_REPO}/main/source.json"
echo "============================================================"
