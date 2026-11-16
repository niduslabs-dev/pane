#!/bin/sh
# Writes a one-item Sparkle appcast for a release DMG to stdout. The release workflow
# publishes it as the release's appcast.xml asset; the app reads the latest release's copy
# (SUFeedURL). Pane only ever needs the newest item, so the feed holds just that one.
#
# Usage: scripts/appcast.sh <version> <build> <dmg> <ed-signature> <notes.md> [download-url]
#   version       CFBundleShortVersionString, shown to people ("0.9.0")
#   build         CFBundleVersion, what Sparkle compares
#   dmg           the signed, notarized DMG (for its length)
#   ed-signature  `sign_update -p` output for the DMG
#   notes.md      release notes as "- " lines; the first three become the popup's lines
#   download-url  default: the GitHub release asset for v<version>
set -eu
VERSION=$1; BUILD=$2; DMG=$3; SIGNATURE=$4; NOTES=$5
REPO=https://github.com/niduslabs-dev/pane
URL=${6:-$REPO/releases/download/v$VERSION/Pane-$VERSION.dmg}
LENGTH=$(stat -f %z "$DMG")
MIN_MACOS=15.0
DATE=$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')

escape() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'; }

# "- line" or "* line" items become <li>s; anything else is left out of the feed.
ITEMS=$(grep -E '^[[:space:]]*[-*][[:space:]]+' "$NOTES" | sed -E 's/^[[:space:]]*[-*][[:space:]]+//' | escape |
    sed -e 's|^|        \&lt;li\&gt;|' -e 's|$|\&lt;/li\&gt;|')

cat <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Pane</title>
    <link>$REPO</link>
    <language>en</language>
    <item>
      <title>Pane $VERSION</title>
      <pubDate>$DATE</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_MACOS</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>$REPO/releases/tag/v$VERSION</sparkle:fullReleaseNotesLink>
      <description>
        &lt;ul&gt;
$ITEMS
        &lt;/ul&gt;
      </description>
      <enclosure url="$URL" length="$LENGTH" type="application/octet-stream" sparkle:edSignature="$SIGNATURE"/>
    </item>
  </channel>
</rss>
XML
