#!/bin/sh
# Builds Pane.app into build/Pane.app: compiles the Pane product through scripts/swift.sh,
# compiles the asset catalog (Pane's custom symbols, from scripts/make-symbols.py) with actool,
# bundles the emulator takeover script, writes the Info.plist and signs it ad hoc with the
# hardened runtime. No keychain or signing
# identity is used; Developer ID signing comes with shipping. Not sandboxed: the App Sandbox
# blocks the emulator's registration folder.
#
# Usage: scripts/build-app.sh            release build
#        scripts/build-app.sh --debug    debug build
set -eu
cd "$(dirname "$0")/.."

CONFIG=release
[ "${1:-}" = "--debug" ] && CONFIG=debug
# A debug build is a separate app to macOS (own bundle ID and name), so it never meets a
# release copy in Launch Services.
BUNDLE_ID=dev.niduslabs.pane
DISPLAY_NAME=Pane
if [ "$CONFIG" = debug ]; then BUNDLE_ID=dev.niduslabs.pane.debug; DISPLAY_NAME="Pane (Debug)"; fi

VERSION=0.1.0
BUILD_NUMBER=1
MIN_MACOS=15.0
APP=build/Pane.app

scripts/swift.sh build -c "$CONFIG" --product Pane
BIN_DIR=$(scripts/swift.sh build -c "$CONFIG" --show-bin-path)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# SwiftPM records the deployment target as the SDK version, so AppKit would draw Pane in its
# pre-macOS 26 compatibility look (no Liquid Glass chrome, small traffic lights). Record the
# SDK it was really built with, as Xcode does.
SDK_VERSION=$(xcrun --sdk macosx --show-sdk-version)
vtool -set-build-version macos "$MIN_MACOS" "$SDK_VERSION" -replace -output "$APP/Contents/MacOS/Pane" "$BIN_DIR/Pane"

# actool is Xcode's; clear Homebrew's LLVM env for it as swift.sh does.
env -u CC -u CXX -u CPPFLAGS -u LDFLAGS -u LIBRARY_PATH xcrun actool Resources/Assets.xcassets \
    --compile "$APP/Contents/Resources" --platform macosx --minimum-deployment-target "$MIN_MACOS" \
    --output-partial-info-plist "build/assets-partial.plist" >/dev/null
cp scripts/emulator-takeover.sh "$APP/Contents/Resources/emulator-takeover.sh"

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
    <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>NSHumanReadableCopyright</key><string>Nidus Labs</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
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

codesign --force --sign - --options runtime --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP ($CONFIG)"
