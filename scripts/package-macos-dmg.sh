#!/usr/bin/env bash
set -euo pipefail

bundle="${1:?usage: package-macos-dmg.sh Spun.app output.dmg [notarize]}"
image="${2:?missing disk image output path}"
notarize="${3:-OFF}"

for tool in codesign ditto hdiutil; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Required macOS packaging tool not found: $tool" >&2
        exit 1
    fi
done
if [[ ! -d "$bundle" ]]; then
    echo "App bundle not found: $bundle" >&2
    exit 1
fi

codesign --verify --deep --strict "$bundle"

if [[ "$notarize" == "ON" ]]; then
    profile="${SPUN_NOTARY_KEYCHAIN_PROFILE:-}"
    if [[ -z "$profile" ]]; then
        echo "Set SPUN_NOTARY_KEYCHAIN_PROFILE to a notarytool keychain profile." >&2
        exit 1
    fi
    if ! command -v xcrun >/dev/null 2>&1; then
        echo "Notarization requires xcrun from Xcode or the Xcode Command Line Tools." >&2
        exit 1
    fi
    xcrun notarytool submit "$bundle" --keychain-profile "$profile" --wait
    xcrun stapler staple "$bundle"
    xcrun stapler validate "$bundle"
fi

image_dir="$(dirname -- "$image")"
mkdir -p "$image_dir"
stage="$(mktemp -d "${TMPDIR:-/tmp}/spun-dmg.XXXXXX")"
trap 'rm -rf "$stage"' EXIT

ditto "$bundle" "$stage/Spun.app"
ln -s /Applications "$stage/Applications"
hdiutil create -volname "Spun" -srcfolder "$stage" \
    -ov -format UDZO "$image"

if [[ "$notarize" == "ON" ]]; then
    xcrun notarytool submit "$image" --keychain-profile "$profile" --wait
    xcrun stapler staple "$image"
    xcrun stapler validate "$image"
fi

echo "Created macOS release image: $image"
