#!/bin/sh
# Packs build/Pane.app into build/Pane-<version>.dmg (the app beside an Applications link),
# then, when the environment asks for it, signs, notarizes and staples the image. With no
# environment set it only builds an unsigned image, so the packaging can be checked locally;
# releases are made by .github/workflows/release.yml, never from a laptop.
#
# Usage: scripts/package-dmg.sh <version>
#
# Environment (all optional):
#   SIGN_IDENTITY     Developer ID identity that signs the image (default "-": not signed)
#   NOTARY_KEY        path to the App Store Connect API key (.p8); with NOTARY_KEY_ID and
#                     NOTARY_ISSUER_ID, the image is notarized, stapled and assessed
#   NOTARY_KEY_ID     the key's ID
#   NOTARY_ISSUER_ID  the issuer ID
#   DMG               where to write the image (default build/Pane-<version>.dmg)
set -eu
cd "$(dirname "$0")/.."

VERSION=${1:?usage: scripts/package-dmg.sh <version>}
APP=build/Pane.app
DMG=${DMG:-build/Pane-$VERSION.dmg}
SIGN_IDENTITY=${SIGN_IDENTITY:--}
NOTARY_TIMEOUT=30m

[ -d "$APP" ] || { echo "error: $APP is missing; run scripts/build-app.sh first" >&2; exit 1; }
BUILT=$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")
[ "$BUILT" = "$VERSION" ] || { echo "error: $APP is version $BUILT, not $VERSION" >&2; exit 1; }

STAGE=$(mktemp -d -t pane-dmg)
WORK=$(mktemp -d -t pane-notary)
trap 'rm -rf "$STAGE" "$WORK"' EXIT
ditto "$APP" "$STAGE/Pane.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname Pane -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null

if [ "$SIGN_IDENTITY" != - ]; then
    codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"
    codesign --verify --verbose=2 "$DMG"
fi

if [ -n "${NOTARY_KEY:-}" ] && [ -n "${NOTARY_KEY_ID:-}" ] && [ -n "${NOTARY_ISSUER_ID:-}" ]; then
    [ "$SIGN_IDENTITY" != - ] || { echo "error: notarizing needs SIGN_IDENTITY" >&2; exit 1; }
    RESULT=$WORK/notary.json
    if ! xcrun notarytool submit "$DMG" --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" \
        --issuer "$NOTARY_ISSUER_ID" --wait --timeout "$NOTARY_TIMEOUT" --output-format json > "$RESULT"; then
        cat "$RESULT"
        ID=$(plutil -extract id raw "$RESULT" 2>/dev/null || true)
        [ -n "$ID" ] && xcrun notarytool log "$ID" --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" \
            --issuer "$NOTARY_ISSUER_ID"
        exit 1
    fi
    cat "$RESULT"
    [ "$(plutil -extract status raw "$RESULT")" = Accepted ]
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
    echo "Packed $DMG (signed $SIGN_IDENTITY, notarized, stapled)"
else
    echo "Packed $DMG (signed $SIGN_IDENTITY, not notarized: NOTARY_KEY, NOTARY_KEY_ID and NOTARY_ISSUER_ID not set)"
fi
