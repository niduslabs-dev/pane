#!/bin/sh
# Builds Pane.app into build/Pane.app: compiles the Pane product through scripts/swift.sh,
# compiles the asset catalog (Pane's custom symbols, from scripts/make-symbols.py) with actool,
# bundles the emulator takeover script and Sparkle.framework, writes the Info.plist and signs
# it inside out with the hardened runtime: ad hoc by default (no keychain or identity is
# used), Developer ID in the release workflow. Not sandboxed: the App Sandbox blocks the
# emulator's registration folder.
#
# Usage: scripts/build-app.sh            release build
#        scripts/build-app.sh --debug    debug build
# PANE_APP=<path> builds the app somewhere else, so a check's debug copy never replaces the
# copy that is running from build/. PANE_BUNDLE_ID=<id> gives that copy its own preferences, so
# a check that flips settings never changes another copy's.
#
# Environment (all optional):
#   VERSION             CFBundleShortVersionString (default 0.1.0)
#   BUILD               CFBundleVersion, what Sparkle compares (default: VERSION)
#   SIGN_IDENTITY       codesign identity (default "-", ad hoc); a real identity also gets a
#                       secure timestamp
#   SPARKLE_PUBLIC_KEY  SUPublicEDKey. Default: the release key for a Developer ID build,
#                       none for an ad hoc build, which then never updates itself. A local
#                       update test passes a throwaway key's public half.
set -eu
cd "$(dirname "$0")/.."

CONFIG=release
[ "${1:-}" = "--debug" ] && CONFIG=debug
# A debug build is a separate app to macOS (own bundle ID and name), so it never meets a
# release copy in Launch Services.
BUNDLE_ID=dev.niduslabs.pane
DISPLAY_NAME=Pane
if [ "$CONFIG" = debug ]; then BUNDLE_ID=dev.niduslabs.pane.debug; DISPLAY_NAME="Pane (Debug)"; fi
BUNDLE_ID=${PANE_BUNDLE_ID:-$BUNDLE_ID}

VERSION=${VERSION:-0.1.0}
BUILD_NUMBER=${BUILD:-$VERSION}
SIGN_IDENTITY=${SIGN_IDENTITY:--}
# The public half of the EdDSA key that signs release DMGs (private half: the
# SPARKLE_ED_PRIVATE_KEY secret). Sparkle refuses any update not signed with it.
# Empty until the key is generated (plans/pane-ship.md in the workspace repo, "Jatin's steps").
RELEASE_SPARKLE_PUBLIC_KEY=
FEED_URL=https://github.com/niduslabs-dev/pane/releases/latest/download/appcast.xml
MIN_MACOS=15.0
APP=${PANE_APP:-build/Pane.app}

# Only a Developer ID build updates itself: a local ad hoc copy must never be replaced by a
# release behind the developer's back.
if [ "$SIGN_IDENTITY" = - ]; then
    SPARKLE_PUBLIC_KEY=${SPARKLE_PUBLIC_KEY:-}
else
    SPARKLE_PUBLIC_KEY=${SPARKLE_PUBLIC_KEY:-$RELEASE_SPARKLE_PUBLIC_KEY}
    if [ -z "$SPARKLE_PUBLIC_KEY" ]; then
        echo "error: a Developer ID build needs the update key: set RELEASE_SPARKLE_PUBLIC_KEY in $0" >&2
        exit 1
    fi
fi

scripts/swift.sh build -c "$CONFIG" --product Pane
BIN_DIR=$(scripts/swift.sh build -c "$CONFIG" --show-bin-path)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
# SwiftPM records the deployment target as the SDK version, so AppKit would draw Pane in its
# pre-macOS 26 compatibility look (no Liquid Glass chrome, small traffic lights). Record the
# SDK it was really built with, as Xcode does.
SDK_VERSION=$(xcrun --sdk macosx --show-sdk-version)
vtool -set-build-version macos "$MIN_MACOS" "$SDK_VERSION" -replace -output "$APP/Contents/MacOS/Pane" "$BIN_DIR/Pane"

# SwiftPM links Sparkle with an @rpath install name but only adds @loader_path (where it
# leaves the framework in .build); the bundle keeps it in Contents/Frameworks. The build also
# leaves an absolute rpath to its own folder: removed, so the bundle can only ever load the
# Sparkle it carries.
for RPATH in $(otool -l "$APP/Contents/MacOS/Pane" | awk '/LC_RPATH/{getline; getline; print $2}' | grep '/\.build/' || true); do
    install_name_tool -delete_rpath "$RPATH" "$APP/Contents/MacOS/Pane" 2>/dev/null
done
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/Pane" 2>/dev/null
# Sparkle's XPC services exist for sandboxed apps only (Sparkle's Sandboxing guide, "Removing
# XPC Services"); Pane isn't sandboxed, so they're left out: less to sign and notarize.
ditto "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices"
rm -f "$APP/Contents/Frameworks/Sparkle.framework/XPCServices"

# actool is Xcode's; clear Homebrew's LLVM env for it as swift.sh does.
env -u CC -u CXX -u CPPFLAGS -u LDFLAGS -u LIBRARY_PATH xcrun actool Resources/Assets.xcassets \
    --compile "$APP/Contents/Resources" --platform macosx --minimum-deployment-target "$MIN_MACOS" \
    --output-partial-info-plist "$(dirname "$APP")/assets-partial.plist" >/dev/null
cp scripts/emulator-takeover.sh "$APP/Contents/Resources/emulator-takeover.sh"

# The app icon, once one is chosen: generated in the Nidus Labs assets repo and committed
# here as Resources/AppIcon.icns. Until then Pane has the generic icon.
ICON_KEYS=
if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
    ICON_KEYS="<key>CFBundleIconFile</key><string>AppIcon</string>"
fi

# Sparkle: Pane draws every surface (UpdateDriver). Checks daily without asking and
# downloads in the background unless the user turns that off. No
# SUEnableInstallerLauncherService: that's for sandboxed apps. Without these keys the app
# never starts Sparkle (UpdateDriver.shouldStart).
UPDATE_KEYS=
if [ -n "$SPARKLE_PUBLIC_KEY" ]; then
    UPDATE_KEYS="<key>SUFeedURL</key><string>$FEED_URL</string>
    <key>SUPublicEDKey</key><string>$SPARKLE_PUBLIC_KEY</string>
    <key>SUEnableAutomaticChecks</key><true/>
    <key>SUAutomaticallyUpdate</key><true/>
    <key>SUScheduledCheckInterval</key><integer>86400</integer>
    <key>SUEnableSystemProfiling</key><false/>"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>Pane</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>$DISPLAY_NAME</string>
    <key>CFBundleDisplayName</key><string>$DISPLAY_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    $ICON_KEYS
    <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>NSHumanReadableCopyright</key><string>Nidus Labs</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
    $UPDATE_KEYS
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key><string>$BUNDLE_ID.attach</string>
            <key>CFBundleURLSchemes</key><array><string>pane</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null

# Inside out, as Sparkle's guide lists it, never --deep: each nested executable gets the
# hardened runtime and the identity, then the framework, then the app.
if [ "$SIGN_IDENTITY" = - ]; then TIMESTAMP=--timestamp=none; else TIMESTAMP=--timestamp; fi
sign() { codesign --force --sign "$SIGN_IDENTITY" --options runtime "$TIMESTAMP" "$@"; }
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
sign "$SPARKLE/Versions/B/Autoupdate"
sign "$SPARKLE/Versions/B/Updater.app"
sign "$SPARKLE"
if [ "$SIGN_IDENTITY" = - ]; then
    # Ad hoc signatures carry no Team ID, so the hardened runtime's library validation would
    # refuse to load the embedded Sparkle. Local builds only; a Developer ID build signs both
    # with one team and keeps library validation on.
    ENTITLEMENTS=$(mktemp -t pane-entitlements)
    trap 'rm -f "$ENTITLEMENTS"' EXIT
    cat > "$ENTITLEMENTS" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>com.apple.security.cs.disable-library-validation</key><true/></dict></plist>
XML
    sign --entitlements "$ENTITLEMENTS" "$APP"
else
    sign "$APP"
fi
codesign --verify --deep --strict "$APP"
if [ -n "$SPARKLE_PUBLIC_KEY" ]; then UPDATES="updates on"; else UPDATES="updates off"; fi
echo "Built $APP ($CONFIG, $VERSION ($BUILD_NUMBER), signed $SIGN_IDENTITY, $UPDATES)"
