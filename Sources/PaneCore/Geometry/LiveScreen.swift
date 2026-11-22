import CoreGraphics

/// The screen Android is showing right now, which on a foldable isn't always the one
/// `config.ini` describes (board 27).
public enum LiveScreen {
    /// The device's live screen size, portrait: the folded screen when a frame carries
    /// `foldedDisplay`, else the configured screen (`hw.lcd`). `getDisplayConfigurations` never
    /// changes on a fold and `wm size` overrides change neither the stream nor touch, so
    /// neither counts (`.claude/research/fold-stretch.md`).
    public static func size(foldedDisplay: PixelSize?, configured: PixelSize?) -> PixelSize? {
        foldedDisplay ?? configured
    }

    /// Whether a frame belongs to a stream asked for at `requested`: a frame whose live size
    /// differs is dropped, and the window reshapes. Without a size on either side (no
    /// `config.ini`) there is nothing to compare, so every frame belongs.
    public static func frame(liveSize: PixelSize?, matches requested: PixelSize?) -> Bool {
        guard let liveSize, let requested else { return true }
        return liveSize == requested
    }

    /// The size worth remembering for an AVD: the live size when it differs from the
    /// configured one (folded), else nil, so an unfolded device stores nothing.
    public static func remembered(liveSize: PixelSize?, configured: PixelSize?) -> PixelSize? {
        guard let liveSize, liveSize != configured else { return nil }
        return liveSize
    }

    /// Reads a remembered size written by `stored(_:)` ("1080x2424").
    public static func parse(_ text: String) -> PixelSize? {
        let parts = text.split(separator: "x")
        guard parts.count == 2, let width = Int(parts[0]), let height = Int(parts[1]), width > 0, height > 0 else {
            return nil
        }
        return PixelSize(width: width, height: height)
    }

    public static func stored(_ size: PixelSize) -> String { "\(size.width)x\(size.height)" }
}

/// Which screen height the window shows (board 27, item 7).
///
/// Pane keeps the height the user chose and shows the larger of it and the smallest height for
/// the current shape, so a raise forced by a narrow shape (a folded Fold at the minimum width)
/// never sticks: unfolding or turning back returns to the chosen height. A manual size is also
/// shrunk, without remembering it, when it no longer fits the display.
public enum ScreenHeightRule {
    /// `displayFit` is the largest height that fits the display for this shape, applied to
    /// manual sizes only (nil for the Window menu's fixed sizes, which may hang off the bottom).
    public static func shown(chosen: CGFloat, minimum: CGFloat, displayFit: CGFloat? = nil) -> CGFloat {
        let capped = displayFit.map { min(chosen, $0) } ?? chosen
        return max(capped, minimum)
    }
}

extension DeviceFrameLayout {
    /// The frame part way from one layout to another, for the reshape's morph: every rect,
    /// radius and the window size move together by `progress` (0 is `from`, 1 is `to`;
    /// clamped, so a spring's overshoot never takes the window past its target).
    ///
    /// Side buttons morph with the body when both layouts put them on the same edge (a fold);
    /// across a turn they take `to`'s places, since the window hides them while it turns.
    public static func interpolated(from: DeviceFrameLayout, to: DeviceFrameLayout, progress: CGFloat)
        -> DeviceFrameLayout
    {
        let t = min(max(progress, 0), 1)
        var layout = to
        layout.screenHeight = lerp(from.screenHeight, to.screenHeight, t)
        layout.bodyRect = lerp(from.bodyRect, to.bodyRect, t)
        layout.screenRect = lerp(from.screenRect, to.screenRect, t)
        layout.bodyRadius = lerp(from.bodyRadius, to.bodyRadius, t)
        layout.screenRadius = lerp(from.screenRadius, to.screenRadius, t)
        layout.windowContentSize = CGSize(
            width: lerp(from.windowContentSize.width, to.windowContentSize.width, t),
            height: lerp(from.windowContentSize.height, to.windowContentSize.height, t))
        let sameEdges = from.buttons.map(\.edge) == to.buttons.map(\.edge)
        if sameEdges {
            layout.buttons = zip(from.buttons, to.buttons).map { start, end in
                var button = end
                button.visibleRect = lerp(start.visibleRect, end.visibleRect, t)
                button.hitRect = lerp(start.hitRect, end.hitRect, t)
                return button
            }
        }
        return layout
    }

    private static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

    private static func lerp(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
        CGRect(
            x: lerp(a.minX, b.minX, t), y: lerp(a.minY, b.minY, t), width: lerp(a.width, b.width, t),
            height: lerp(a.height, b.height, t))
    }
}
