#!/bin/sh
# The uninstall of Pane 1.0's "Show All Emulators in Pane", kept so the first launch of a newer
# Pane can undo it (EmulatorTakeover.runLegacyUninstall). 1.0 built a shadow SDK at
# ~/Library/Android/pane-sdk and added a marked block to the shell configs pointing ANDROID_HOME
# at it; this removes both (each config is backed up first). Newer Panes wrap the launcher in
# the real SDK instead (Sources/PaneTakeover).
#
# Usage: emulator-takeover.sh uninstall
#
# Tests point it elsewhere with PANE_SHADOW_SDK, PANE_FISH_CONFIG and PANE_ZSH_CONFIGS
# (space-separated).
set -eu

SHADOW=${PANE_SHADOW_SDK:-$HOME/Library/Android/pane-sdk}
FISH_CONFIG=${PANE_FISH_CONFIG:-$HOME/.config/fish/config.fish}
ZSH_CONFIGS=${PANE_ZSH_CONFIGS:-"$HOME/.zprofile $HOME/.zshrc"}
BEGIN_MARK='# >>> pane emulator takeover >>>'
END_MARK='# <<< pane emulator takeover <<<'
MARKER="$SHADOW/.pane-takeover"

die() {
    echo "emulator-takeover: $*" >&2
    exit 1
}

has_block() { [ -f "$1" ] && grep -qF "$BEGIN_MARK" "$1"; }

backup() {
    [ -f "$1" ] || return 0
    copy="$1.pane-backup-$(date +%Y%m%d-%H%M%S)"
    n=1
    while [ -e "$copy" ]; do copy="$1.pane-backup-$(date +%Y%m%d-%H%M%S)-$n"; n=$((n + 1)); done
    cp -p "$1" "$copy"
    echo "backed up $1 to $copy"
}

# Writes the file without the block (if any), through a temp file in the same folder.
remove_block() {
    has_block "$1" || return 0
    tmp="$1.pane-tmp.$$"
    awk -v begin="$BEGIN_MARK" -v end="$END_MARK" '
        $0 == begin { skipping = 1; next }
        skipping && $0 == end { skipping = 0; next }
        !skipping { print }
    ' "$1" >"$tmp"
    cat "$tmp" >"$1"
    rm -f "$tmp"
}

uninstall() {
    for file in "$FISH_CONFIG" $ZSH_CONFIGS; do
        if has_block "$file"; then
            backup "$file"
            remove_block "$file"
            echo "removed the block from $file"
        fi
    done
    if [ -f "$MARKER" ]; then
        rm -rf "$SHADOW"
        echo "removed $SHADOW"
    elif [ -e "$SHADOW" ]; then
        echo "left $SHADOW alone: it isn't Pane's" >&2
    fi
    echo "Uninstalled. Shells opened from now on use the real SDK."
}

case ${1:-} in
    uninstall) uninstall ;;
    *) die "usage: emulator-takeover.sh uninstall" ;;
esac
