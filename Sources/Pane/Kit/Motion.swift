import SwiftUI

// The kit's motion, after Purge's techniques (the studio guide's behaviours), with the
// values in `Kit.Motion`. Each piece reads Reduce Motion and falls back to a plain fade or
// to no animation at all.

/// Blur, fade and drift: the state of a view on its way in or out.
private struct BlurFade: ViewModifier {
    let blur: CGFloat
    let opacity: Double
    let offset: CGSize

    func body(content: Content) -> some View {
        content.blur(radius: blur).opacity(opacity).offset(offset)
    }
}

extension AnyTransition {
    /// Purge's `blurFade`: blurred, transparent and moved by `offsetY` while inactive.
    static func blurFade(radius: CGFloat, offsetY: CGFloat) -> AnyTransition {
        .modifier(
            active: BlurFade(blur: radius, opacity: 0, offset: CGSize(width: 0, height: offsetY)),
            identity: BlurFade(blur: 0, opacity: 1, offset: .zero))
    }

    /// The status line swap: the old line blurs up and away, the new one sharpens in from
    /// below. Reduce Motion: a cross-fade.
    static func statusSwap(reduceMotion: Bool) -> AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .blurFade(radius: Kit.Motion.swapBlur, offsetY: Kit.Motion.swapOffset),
                removal: .blurFade(radius: Kit.Motion.swapBlur, offsetY: -Kit.Motion.swapOffset))
    }
}

/// Swaps its content with the status blur whenever `key` changes. The old and new content
/// overlap in a `ZStack`, left-aligned, so the line never jumps.
struct StatusSwap<Key: Hashable, Content: View>: View {
    let key: Key
    @ViewBuilder var content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .leading) {
            content
                .id(key)
                .transition(.statusSwap(reduceMotion: reduceMotion))
        }
        .animation(reduceMotion ? Kit.Motion.fade : Kit.Motion.swap, value: key)
    }
}
