import Foundation

/// The script that takes the place of `<sdk>/emulator/emulator` while "Show all emulators in
/// Pane" is on. The real launcher sits beside it as `emulator-real`.
///
/// - An AVD launch (`@name`, `-avd name`) asks Pane to show that AVD (`open -g -b <bundle id>`,
///   which starts Pane in the background when it isn't running), then runs the real launcher
///   with `-no-window` added (before any `-qemu`, whose arguments are QEMU's).
/// - `-no-window`, `-qt-hide-window` (Android Studio's tool window), info calls
///   (`-list-avds`, `-version`…) and `PANE_TAKEOVER=0` pass through untouched and never open Pane.
/// - When Pane can't be opened (moved to the Trash), the real launcher runs as it would
///   without Pane, window and all.
///
/// It finds `emulator-real` beside itself, so it works under any SDK path, and `exec`s it, so
/// the caller's PID is the emulator's (Expo's "quit before it opened" check relies on that).
public enum TakeoverWrapper {
    /// The second line of every wrapper Pane writes; how Pane tells its own script from
    /// someone else's.
    public static let marker = "# pane-emulator-wrapper"
    /// The real launcher's name beside the wrapper.
    public static let realName = "emulator-real"
    public static let launcherName = "emulator"

    /// The wrapper for the Pane with `bundleID`. Bundle IDs are reverse-DNS (letters, digits,
    /// `.` and `-`), so it is safe to put between single quotes.
    public static func script(bundleID: String) -> String {
        precondition(bundleID.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" })
        return """
            #!/bin/sh
            \(marker) v1
            # Written by Pane ("Show all emulators in Pane"). Turning the setting off puts the real
            # launcher (emulator-real, beside this file) back. A launch of an AVD runs headless and
            # opens in Pane; everything else goes straight through.
            here=$(cd "$(dirname "$0")" && pwd -P)
            REAL="$here/\(realName)"
            [ -x "$REAL" ] || { echo "pane: no emulator at $REAL" >&2; exit 127; }
            [ "${PANE_TAKEOVER:-1}" = 0 ] && exec "$REAL" "$@"

            avd=
            pass=0
            expect_avd=0
            for arg in "$@"; do
                if [ $expect_avd = 1 ]; then avd=$arg; expect_avd=0; continue; fi
                case $arg in
                    -qemu) break ;;
                    -avd) expect_avd=1 ;;
                    @?*) avd=${arg#@} ;;
                    -no-window | -qt-hide-window) pass=1 ;;
                    -list-avds | -version | -help | -help-* | -accel-check | -list-cores | -snapshot-list) pass=1 ;;
                esac
            done
            if [ -z "$avd" ] || [ $pass = 1 ]; then exec "$REAL" "$@"; fi

            open -g -b '\(bundleID)' "pane://attach?avd=$avd" --args --attach "$avd" >/dev/null 2>&1 || exec "$REAL" "$@"

            count=$#
            added=0
            for arg in "$@"; do
                if [ $added = 0 ] && [ "$arg" = -qemu ]; then set -- "$@" -no-window; added=1; fi
                set -- "$@" "$arg"
            done
            shift $count
            [ $added = 1 ] || set -- "$@" -no-window
            exec "$REAL" "$@"

            """
    }

    /// Whether `data` (a launcher's first bytes or all of it) is a wrapper Pane wrote.
    public static func isWrapper(_ data: Data) -> Bool {
        String(decoding: data.prefix(256), as: UTF8.self).contains(marker)
    }
}
