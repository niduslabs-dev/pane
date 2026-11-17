#!/bin/sh
# Copies the generated design tokens from the Nidus Labs assets repo (`npm run build:tokens`
# there). Never edit Sources/Pane/Theme/ThemeTokens.swift by hand: change a shared value in
# assets/tokens.json, rebuild there, then run this. The copy is committed, because CI and the
# release build don't have the assets repo. `--check` fails when the copy differs from the
# assets repo's. Usage: scripts/sync-tokens.sh [--check] [path to the assets repo]
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CHECK=
[ "${1:-}" = "--check" ] && { CHECK=1; shift; }
ASSETS=${1:-"$ROOT/../assets"}
SRC="$ASSETS/dist/tokens/ThemeTokens.swift"
DEST="$ROOT/Sources/Pane/Theme/ThemeTokens.swift"
if [ -n "$CHECK" ]; then
    cmp -s "$SRC" "$DEST" || { echo "ThemeTokens.swift is stale: run scripts/sync-tokens.sh" >&2; exit 1; }
    exit 0
fi
mkdir -p "$(dirname "$DEST")"
cp "$SRC" "$DEST"
echo "Copied $SRC to Sources/Pane/Theme/ThemeTokens.swift"
