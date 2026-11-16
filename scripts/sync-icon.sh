#!/bin/sh
# Copies Pane's app icon from the Nidus Labs assets repo, where it's generated
# (`npm run build` there, then iconutil; see its README). Never edit
# Resources/AppIcon.icns by hand. Usage: scripts/sync-icon.sh [path to the assets repo]
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
ASSETS=${1:-"$ROOT/../assets"}
cp "$ASSETS/apps/pane/Pane.icns" "$ROOT/Resources/AppIcon.icns"
echo "Copied $ASSETS/apps/pane/Pane.icns to Resources/AppIcon.icns"
