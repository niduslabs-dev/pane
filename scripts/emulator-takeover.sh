#!/bin/sh
# Pane's emulator takeover: every emulator launch (Expo's `run:android`, scripts, `emulator -avd`)
# runs headless and shows in Pane instead of opening its own window.
#
# It builds a shadow Android SDK: a folder of symlinks to every top-level entry of the real SDK,
# except `emulator/`, which is a real folder of symlinks to everything in the real emulator folder
# except the `emulator` launcher. That one is a wrapper script: for a launch (`-avd NAME` or
# `@NAME`) it adds `-no-window`, asks Pane to show that AVD, and `exec`s the real launcher; any
# other call (`-list-avds`, `-version`, `-help`...) goes straight through. Shells then point
# ANDROID_HOME, ANDROID_SDK_ROOT and the emulator on PATH at the shadow, through a marked block in
# the shell configs (backed up first). Nothing outside the shadow folder and those blocks changes.
#
# The shadow lives at ~/Library/Android/pane-sdk, next to the real SDK: its path has no spaces,
# because Android's NDK tools break on an SDK path with spaces (Android Studio warns about it).
#
# Usage: emulator-takeover.sh install [--app /path/to/Pane.app]
#        emulator-takeover.sh uninstall
#        emulator-takeover.sh status
#
# Tests point it elsewhere with PANE_REAL_SDK, PANE_SHADOW_SDK, PANE_FISH_CONFIG and
# PANE_ZSH_CONFIGS (space-separated).
set -eu

REAL_SDK=${PANE_REAL_SDK:-$HOME/Library/Android/sdk}
SHADOW=${PANE_SHADOW_SDK:-$HOME/Library/Android/pane-sdk}
FISH_CONFIG=${PANE_FISH_CONFIG:-$HOME/.config/fish/config.fish}
# .zprofile sets the real SDK for login shells, so the block goes after it there; .zshrc covers
# interactive shells that inherited the real SDK from an older parent.
ZSH_CONFIGS=${PANE_ZSH_CONFIGS:-"$HOME/.zprofile $HOME/.zshrc"}
BEGIN_MARK='# >>> pane emulator takeover >>>'
END_MARK='# <<< pane emulator takeover <<<'
MARKER="$SHADOW/.pane-takeover"

die() {
    echo "emulator-takeover: $*" >&2
    exit 1
}

case "$SHADOW" in *' '*) die "the shadow SDK path must not contain spaces: $SHADOW" ;; esac

# Prints the wrapper that replaces the emulator launcher. Paths are baked in at install time.
write_wrapper() {
    cat <<WRAPPER
#!/bin/sh
# Pane's emulator wrapper, written by emulator-takeover.sh (remove with its uninstall).
# A launch of an AVD runs headless and opens in Pane; everything else goes straight through.
REAL_SDK='$REAL_SDK'
SHADOW='$SHADOW'
PANE_APP='$1'
REAL="\$REAL_SDK/emulator/emulator"
[ -x "\$REAL" ] || { echo "pane: no emulator at \$REAL" >&2; exit 127; }

# Mirrors \$1 into \$2 as symlinks, leaving out the entry named \$3, and drops links whose
# target is gone. Runs when the real folder changed (an SDK update).
sync_links() {
    for entry in "\$1"/* "\$1"/.[!.]* "\$1"/..?*; do
        [ -e "\$entry" ] || [ -L "\$entry" ] || continue
        name=\${entry##*/}
        [ "\$name" = "\$3" ] && continue
        [ -e "\$2/\$name" ] || [ -L "\$2/\$name" ] || ln -s "\$entry" "\$2/\$name"
    done
    for link in "\$2"/* "\$2"/.[!.]* "\$2"/..?*; do
        [ -L "\$link" ] && [ ! -e "\$link" ] && rm -f "\$link"
    done
    return 0
}
if [ "\$REAL_SDK/emulator" -nt "\$SHADOW/emulator/.pane-synced" ] || [ "\$REAL_SDK" -nt "\$SHADOW/.pane-synced" ]; then
    sync_links "\$REAL_SDK" "\$SHADOW" emulator && touch "\$SHADOW/.pane-synced"
    sync_links "\$REAL_SDK/emulator" "\$SHADOW/emulator" emulator && touch "\$SHADOW/emulator/.pane-synced"
fi

# Pane missing, or PANE_TAKEOVER=0: the real emulator, window and all.
if [ ! -d "\$PANE_APP" ] || [ "\${PANE_TAKEOVER:-1}" = 0 ]; then exec "\$REAL" "\$@"; fi

avd=
no_window=0
info=0
expect_avd=0
for arg in "\$@"; do
    if [ \$expect_avd = 1 ]; then avd=\$arg; expect_avd=0; continue; fi
    case \$arg in
        -qemu) break ;;
        -avd) expect_avd=1 ;;
        @?*) avd=\${arg#@} ;;
        -no-window) no_window=1 ;;
        -list-avds | -version | -help | -help-* | -accel-check | -list-cores | -snapshot-list) info=1 ;;
    esac
done
if [ -z "\$avd" ] || [ \$info = 1 ]; then exec "\$REAL" "\$@"; fi

# Opens Pane in the background on this AVD (the URL reaches a running Pane; --attach a new one).
open -g -a "\$PANE_APP" "pane://attach?avd=\$avd" --args --attach "\$avd" >/dev/null 2>&1 || true

if [ \$no_window = 1 ]; then exec "\$REAL" "\$@"; fi
# -no-window goes before any -qemu (whose arguments belong to QEMU), else at the end.
count=\$#
added=0
for arg in "\$@"; do
    if [ \$added = 0 ] && [ "\$arg" = -qemu ]; then set -- "\$@" -no-window; added=1; fi
    set -- "\$@" "\$arg"
done
shift \$count
[ \$added = 1 ] || set -- "\$@" -no-window
exec "\$REAL" "\$@"
WRAPPER
}

# Same as the wrapper's sync_links, for install.
sync_links() {
    for entry in "$1"/* "$1"/.[!.]* "$1"/..?*; do
        [ -e "$entry" ] || [ -L "$entry" ] || continue
        name=${entry##*/}
        [ "$name" = "$3" ] && continue
        [ -e "$2/$name" ] || [ -L "$2/$name" ] || ln -s "$entry" "$2/$name"
    done
    for link in "$2"/* "$2"/.[!.]* "$2"/..?*; do
        [ -L "$link" ] && [ ! -e "$link" ] && rm -f "$link"
    done
    return 0
}

fish_block() {
    cat <<BLOCK
$BEGIN_MARK
# Every emulator launch runs headless and shows in Pane. Added by Pane; remove it with Pane's
# "Show All Emulators in Pane" or \`emulator-takeover.sh uninstall\`.
if test -x $SHADOW/emulator/emulator
    set -gx ANDROID_HOME $SHADOW
    set -gx ANDROID_SDK_ROOT $SHADOW
    fish_add_path --global --move --path $SHADOW/emulator
end
$END_MARK
BLOCK
}

zsh_block() {
    cat <<BLOCK
$BEGIN_MARK
# Every emulator launch runs headless and shows in Pane. Added by Pane; remove it with Pane's
# "Show All Emulators in Pane" or \`emulator-takeover.sh uninstall\`.
if [ -x $SHADOW/emulator/emulator ]; then
	export ANDROID_HOME=$SHADOW ANDROID_SDK_ROOT=$SHADOW
	case ":\$PATH:" in *":$SHADOW/emulator:"*) ;; *) export PATH="$SHADOW/emulator:\$PATH" ;; esac
fi
$END_MARK
BLOCK
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

# $1 file, $2 block printer. Idempotent: an existing block is replaced in place at the end.
put_block() {
    backup "$1"
    mkdir -p "$(dirname "$1")"
    remove_block "$1"
    if [ -s "$1" ] && [ "$(tail -c 1 "$1")" != "" ]; then echo >>"$1"; fi
    "$2" >>"$1"
    echo "added the block to $1"
}

install() {
    app=$1
    [ -x "$REAL_SDK/emulator/emulator" ] || die "no emulator in the real SDK at $REAL_SDK"
    if [ -e "$SHADOW" ] && [ ! -f "$MARKER" ]; then die "$SHADOW exists and isn't Pane's; not touching it"; fi
    mkdir -p "$SHADOW/emulator"
    echo "real_sdk=$REAL_SDK" >"$MARKER"
    echo "pane_app=$app" >>"$MARKER"
    sync_links "$REAL_SDK" "$SHADOW" emulator
    touch "$SHADOW/.pane-synced"
    sync_links "$REAL_SDK/emulator" "$SHADOW/emulator" emulator
    touch "$SHADOW/emulator/.pane-synced"
    write_wrapper "$app" >"$SHADOW/emulator/emulator.pane-tmp"
    chmod 755 "$SHADOW/emulator/emulator.pane-tmp"
    mv -f "$SHADOW/emulator/emulator.pane-tmp" "$SHADOW/emulator/emulator"
    echo "shadow SDK at $SHADOW (Pane: $app)"
    put_block "$FISH_CONFIG" fish_block
    for file in $ZSH_CONFIGS; do put_block "$file" zsh_block; done
    echo "Installed. Shells opened from now on use it."
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

status() {
    state=installed
    if [ -f "$MARKER" ] && [ -x "$SHADOW/emulator/emulator" ]; then
        echo "shadow SDK: $SHADOW"
        sed 's/^/  /' "$MARKER"
    else
        echo "shadow SDK: none"
        state=not-installed
    fi
    for file in "$FISH_CONFIG" $ZSH_CONFIGS; do
        if has_block "$file"; then echo "block: $file"; else echo "no block: $file"; state=not-installed; fi
    done
    echo "$state"
}

command=${1:-status}
[ $# -gt 0 ] && shift
case $command in
    install)
        app=/Applications/Pane.app
        if [ "${1:-}" = --app ] && [ -n "${2:-}" ]; then app=$2; fi
        case "$app" in /*) ;; *) die "--app needs an absolute path" ;; esac
        case "$app" in *"'"*) die "the app path can't contain a single quote" ;; esac
        install "$app"
        ;;
    uninstall) uninstall ;;
    status) status ;;
    *) die "usage: emulator-takeover.sh install [--app PATH] | uninstall | status" ;;
esac
