#if DEBUG
    import Foundation
    import PaneCore

    /// Debug builds only: `-PaneSwitcherFake <case>` replaces the switcher's emulators with board
    /// 20's examples, so checks can capture states this Mac can't set up with one emulator.
    /// The window's own emulator stays first and real (running, ticked); the others are names
    /// only, and choosing one does what choosing a missing AVD does.
    ///
    /// Cases: `three` (two stopped examples), `starting` (pixel9_api35 starting), `other`
    /// (pixel9_api35 in another window), `long` (a long name and model), `one` (this window's
    /// alone), `none` (no emulators set up).
    enum SwitcherFake {
        static func entries(current: String?) -> [SwitcherEntry]? {
            guard let name = UserDefaults.standard.string(forKey: "PaneSwitcherFake") else { return nil }
            let this = SwitcherEntry(
                name: current ?? "dev_android36", model: "Pixel 8", androidVersion: "Android 16", state: .running,
                isCurrent: true)
            let pixel9 = SwitcherEntry(name: "pixel9_api35", model: "Pixel 9 Pro", androidVersion: "Android 15")
            let tablet = SwitcherEntry(
                name: "tablet_api36", model: "Pixel Tablet", androidVersion: "Android 16", kind: .tablet)
            switch name {
            case "three":
                return [this, pixel9, tablet]
            case "starting":
                var starting = pixel9
                starting.state = .starting
                return [this, starting, tablet]
            case "other":
                var other = pixel9
                other.state = .running
                other.isShownElsewhere = true
                return [this, other, tablet]
            case "long":
                let long = SwitcherEntry(
                    name: "pixel9_pro_fold_api35_playstore", model: "Pixel 9 Pro Fold, inner screen",
                    androidVersion: "Android 15", kind: .foldable, state: .running)
                return [this, long, tablet]
            case "one":
                return [this]
            case "none":
                return []
            default:
                return nil
            }
        }
    }
#endif
