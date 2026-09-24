#!/bin/bash
# Archive, notarize, and publish a GitHub Release ZIP with a Sparkle update entry.
# Usage: ./build_release.sh VERSION --tag RELEASE_TAG [--notes release-notes.html]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
RELEASE_DIR="$REPO_ROOT/build/release"
GITHUB_REPOSITORY="zwyyy456/GitStride"

usage() {
    echo "Usage: $0 VERSION --tag RELEASE_TAG [--notes release-notes.html]" >&2
    exit 1
}

VERSION="${1:-}"
[ -n "$VERSION" ] || usage
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

[[ "$VERSION" =~ ^[0-9]+([.][0-9]+)*$ ]] || usage
[[ "$TAG" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || usage
if [ -n "$NOTES_PATH" ] && [ ! -f "$NOTES_PATH" ]; then
    echo "Release notes file not found: $NOTES_PATH" >&2
    exit 1
fi
if [ -e "$RELEASE_DIR/GitStride-$VERSION.zip" ]; then
    echo "Local release ZIP already exists: $RELEASE_DIR/GitStride-$VERSION.zip" >&2
    exit 1
fi

# The release and tag must already identify the intended source commit.
RELEASE_ASSETS=$(gh release view "$TAG" --repo "$GITHUB_REPOSITORY" --json assets --jq '.assets[].name')
while IFS= read -r ASSET_NAME; do
    if [ "$ASSET_NAME" = "GitStride-$VERSION.zip" ]; then
        echo "GitHub release $TAG already has GitStride-$VERSION.zip." >&2
        exit 1
    fi
done <<< "$RELEASE_ASSETS"

PROJECT_BUILD=$(cd "$REPO_ROOT" && xcrun agvtool what-version -terse)
BUILD_NUMBER=$(python3 - "$PROJECT_BUILD" "$REPO_ROOT/appcast.xml" "$VERSION" <<'PY'
import sys
import xml.etree.ElementTree as ET

project_build, feed_path, version = sys.argv[1:]
if not project_build.isdecimal():
    raise SystemExit(f"Expected an integer project build number, found {project_build!r}.")

builds = [int(project_build)]
namespace = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
for item in ET.parse(feed_path).findall("./channel/item"):
    if item.findtext("sparkle:shortVersionString", namespaces=namespace) == version:
        raise SystemExit(f"Version {version} is already present in appcast.xml.")
    published_build = item.findtext("sparkle:version", namespaces=namespace)
    if published_build:
        if not published_build.isdecimal():
            raise SystemExit(f"Expected an integer published build number, found {published_build!r}.")
        builds.append(int(published_build))

print(max(builds) + 1)
PY
)

mkdir -p "$RELEASE_DIR"
RUN_DIR=$(mktemp -d "$RELEASE_DIR/GitStride-$VERSION-build$BUILD_NUMBER.XXXXXX")
ARCHIVE_PATH="$RUN_DIR/GitStride.xcarchive"
EXPORT_PATH="$RUN_DIR/export"
APP_PATH="$EXPORT_PATH/GitStride.app"
NOTARIZATION_ZIP="$RUN_DIR/GitStride-notarization.zip"

printf 'Building GitStride %s (build %s) in %s\n' "$VERSION" "$BUILD_NUMBER" "$RUN_DIR"
xcodebuild -project "$REPO_ROOT/GitStride.xcodeproj" -scheme GitStride \
    -configuration Release -destination 'generic/platform=macOS' \
    -derivedDataPath "$RELEASE_DIR/DerivedData" \
    -archivePath "$ARCHIVE_PATH" \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" archive

cat > "$RUN_DIR/ExportOptions.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>method</key><string>developer-id</string>
    <key>signingStyle</key><string>manual</string>
    <key>signingCertificate</key><string>Developer ID Application</string>
</dict></plist>
PLIST

xcodebuild -exportArchive -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" -exportOptionsPlist "$RUN_DIR/ExportOptions.plist"
codesign --verify --deep --strict "$APP_PATH"

INFO_PLIST="$APP_PATH/Contents/Info.plist"
EXPORTED_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")
EXPORTED_BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")
if [ "$EXPORTED_VERSION" != "$VERSION" ] || [ "$EXPORTED_BUILD" != "$BUILD_NUMBER" ]; then
    echo "Exported app version/build does not match $VERSION ($BUILD_NUMBER)." >&2
    exit 1
fi
CODE_SIGN_INFO=$(codesign -dv --verbose=4 "$APP_PATH" 2>&1)
if [[ "$CODE_SIGN_INFO" != *"Authority=Developer ID Application:"* ]]; then
    echo "The exported app is not signed with a Developer ID Application certificate." >&2
    exit 1
fi

SPARKLE_BIN="$RELEASE_DIR/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin"
SIGNING_PUBLIC_KEY=$("$SPARKLE_BIN/generate_keys" --account gitstride -p)
BUNDLED_PUBLIC_KEY=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$INFO_PLIST")
if [ "$SIGNING_PUBLIC_KEY" != "$BUNDLED_PUBLIC_KEY" ]; then
    echo "The app's SUPublicEDKey must match the gitstride Sparkle key. See docs/releasing.md." >&2
    exit 1
fi

# The submitted ZIP is temporary: the final ZIP must contain the stapled app.
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$NOTARIZATION_ZIP"
xcrun notarytool submit "$NOTARIZATION_ZIP" --keychain-profile gitstride-notary \
    --wait --timeout 2h --output-format json > "$RUN_DIR/notarization-result.json"
NOTARY_STATUS=$(python3 - "$RUN_DIR/notarization-result.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as result:
    print(json.load(result).get("status", ""))
PY
)
if [ "$NOTARY_STATUS" != Accepted ]; then
    echo "Notarization status: ${NOTARY_STATUS:-unknown}. See $RUN_DIR/notarization-result.json." >&2
    exit 1
fi
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
rm "$NOTARIZATION_ZIP"

printf 'Notarized app: %s\n' "$APP_PATH"
UPDATE_ARGS=("$APP_PATH" --tag "$TAG")
if [ -n "$NOTES_PATH" ]; then
    UPDATE_ARGS+=(--notes "$NOTES_PATH")
fi
"$REPO_ROOT/update_appcast.sh" "${UPDATE_ARGS[@]}"
