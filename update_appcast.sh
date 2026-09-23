#!/bin/bash
# Package a notarized app, upload its signed ZIP, then update the local Sparkle feed.
# Usage: ./update_appcast.sh /path/to/GitStride.app --tag v1.0.1 [--notes release-notes.html]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
RELEASE_DIR="$REPO_ROOT/build/release"
SPARKLE_BIN="$RELEASE_DIR/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin"
GITHUB_REPOSITORY="zwyyy456/GitStride"

usage() {
    echo "Usage: $0 /path/to/GitStride.app --tag RELEASE_TAG [--notes release-notes.html]" >&2
    exit 1
}

APP_PATH="${1:-}"
[ -n "$APP_PATH" ] || usage
shift
TAG=""
NOTES_PATH=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --tag)
            [ "$#" -ge 2 ] || usage
            TAG="$2"
            shift 2
            ;;
        --notes)
            [ "$#" -ge 2 ] || usage
            NOTES_PATH="$2"
            shift 2
            ;;
        *) usage ;;
    esac
done

[ -d "$APP_PATH" ] && [ "$(basename "$APP_PATH")" = "GitStride.app" ] || usage
[[ "$TAG" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || usage
if [ -n "$NOTES_PATH" ] && [ ! -f "$NOTES_PATH" ]; then
    echo "Release notes file not found: $NOTES_PATH" >&2
    exit 1
fi

INFO_PLIST="$APP_PATH/Contents/Info.plist"
if [ ! -f "$INFO_PLIST" ]; then
    echo "The app has no Contents/Info.plist: $APP_PATH" >&2
    exit 1
fi
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")
if [ "$BUNDLE_ID" != "tech.hyperseek.gitstride" ] || [ -z "$VERSION" ] || [ -z "$BUILD_NUMBER" ]; then
    echo "Expected a versioned GitStride Release app, found bundle ID: $BUNDLE_ID" >&2
    exit 1
fi
if ! [[ "$VERSION" =~ ^[0-9]+([.][0-9]+)*$ && "$BUILD_NUMBER" =~ ^[0-9]+([.][0-9]+)*$ ]]; then
    echo "The app's version and build number must contain only numeric components." >&2
    exit 1
fi

codesign --verify --deep --strict "$APP_PATH"
CODE_SIGN_INFO=$(codesign -dv --verbose=4 "$APP_PATH" 2>&1)
if [[ "$CODE_SIGN_INFO" != *"Authority=Developer ID Application:"* ]]; then
    echo "The app is not signed with a Developer ID Application certificate." >&2
    exit 1
fi
xcrun stapler validate "$APP_PATH"

if [ ! -x "$SPARKLE_BIN/generate_appcast" ]; then
    xcodebuild -resolvePackageDependencies -project "$REPO_ROOT/GitStride.xcodeproj" \
        -scheme GitStride -derivedDataPath "$RELEASE_DIR/DerivedData"
fi
if [ ! -x "$SPARKLE_BIN/generate_appcast" ]; then
    echo "Sparkle tools are missing at $SPARKLE_BIN" >&2
    exit 1
fi
SIGNING_PUBLIC_KEY=$("$SPARKLE_BIN/generate_keys" --account gitstride -p)
BUNDLED_PUBLIC_KEY=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$INFO_PLIST")
if [ "$SIGNING_PUBLIC_KEY" != "$BUNDLED_PUBLIC_KEY" ]; then
    echo "The app's SUPublicEDKey does not match the gitstride Sparkle signing key." >&2
    exit 1
fi

ZIP_NAME="GitStride-$VERSION.zip"
LOCAL_ZIP_PATH="$RELEASE_DIR/$ZIP_NAME"
if [ -e "$LOCAL_ZIP_PATH" ]; then
    echo "Local archive already exists: $LOCAL_ZIP_PATH" >&2
    exit 1
fi
RELEASE_ASSETS=$(gh release view "$TAG" --repo "$GITHUB_REPOSITORY" --json assets --jq '.assets[].name')
while IFS= read -r ASSET_NAME; do
    if [ "$ASSET_NAME" = "$ZIP_NAME" ]; then
        echo "GitHub release $TAG already has $ZIP_NAME; existing assets are never replaced." >&2
        exit 1
    fi
done <<< "$RELEASE_ASSETS"

python3 - "$REPO_ROOT/appcast.xml" "$BUILD_NUMBER" <<'PY'
import sys
import xml.etree.ElementTree as ET

feed, new_build = sys.argv[1:]
namespace = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
new_parts = tuple(map(int, new_build.split(".")))
for item in ET.parse(feed).findall("./channel/item"):
    published_build = item.findtext("sparkle:version", namespaces=namespace)
    if not published_build:
        continue
    old_parts = tuple(map(int, published_build.split(".")))
    width = max(len(new_parts), len(old_parts))
    if new_parts + (0,) * (width - len(new_parts)) <= old_parts + (0,) * (width - len(old_parts)):
        raise SystemExit(f"Build {new_build} must exceed published build {published_build}.")
PY

STAGING_DIR=$(mktemp -d "${TMPDIR:-/tmp}/gitstride-appcast.XXXXXX")
trap 'rm -rf "$STAGING_DIR"' EXIT
ZIP_PATH="$STAGING_DIR/$ZIP_NAME"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
cp "$REPO_ROOT/appcast.xml" "$STAGING_DIR/appcast.xml"
if [ -n "$NOTES_PATH" ]; then
    cp "$NOTES_PATH" "$STAGING_DIR/${ZIP_NAME%.zip}.html"
fi

DOWNLOAD_URL="https://github.com/$GITHUB_REPOSITORY/releases/download/$TAG/$ZIP_NAME"
"$SPARKLE_BIN/generate_appcast" \
    --account gitstride \
    --download-url-prefix "https://github.com/$GITHUB_REPOSITORY/releases/download/$TAG/" \
    --link "https://gitstride.hyperseek.tech" \
    --versions "$BUILD_NUMBER" \
    --embed-release-notes --maximum-deltas 0 --maximum-versions 0 \
    "$STAGING_DIR"

SIGNATURE=$(python3 - "$STAGING_DIR/appcast.xml" "$ZIP_PATH" "$DOWNLOAD_URL" "$VERSION" "$BUILD_NUMBER" <<'PY'
import os
import sys
import xml.etree.ElementTree as ET

feed, archive, expected_url, version, build = sys.argv[1:]
namespace = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
matches = []
for item in ET.parse(feed).findall("./channel/item"):
    enclosure = item.find("enclosure")
    if enclosure is not None and enclosure.get("url") == expected_url:
        matches.append((item, enclosure))
if len(matches) != 1:
    raise SystemExit("Sparkle did not generate exactly one entry for the requested release URL.")
item, enclosure = matches[0]
if item.findtext("sparkle:shortVersionString", namespaces=namespace) != version:
    raise SystemExit("The appcast display version does not match the exported app.")
if item.findtext("sparkle:version", namespaces=namespace) != build:
    raise SystemExit("The appcast build number does not match the exported app.")
if enclosure.get("length") != str(os.path.getsize(archive)):
    raise SystemExit("The appcast archive length does not match the ZIP.")
signature = enclosure.get("{" + namespace["sparkle"] + "}edSignature")
if not signature:
    raise SystemExit("Sparkle did not sign the ZIP.")
print(signature)
PY
)
"$SPARKLE_BIN/sign_update" --account gitstride --verify "$ZIP_PATH" "$SIGNATURE"

gh release upload "$TAG" "$ZIP_PATH" --repo "$GITHUB_REPOSITORY"
mkdir -p "$RELEASE_DIR"
cp "$ZIP_PATH" "$LOCAL_ZIP_PATH"
cp "$STAGING_DIR/appcast.xml" "$REPO_ROOT/appcast.xml"
printf 'Uploaded %s to %s and updated local appcast.xml.\n' "$LOCAL_ZIP_PATH" "$TAG"
printf 'Publish appcast.xml to main after reviewing the release asset; this script does not push Git.\n'
