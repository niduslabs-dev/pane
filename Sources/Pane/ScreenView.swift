import AppKit
import PaneCore
import SwiftUI

/// The emulator's screen: a layer-backed view whose layer shows the latest frame as a `CGImage`,
/// clipped to the screen's rounded corners, and which reports the pointer in its own
/// coordinates (y down).
///
/// The spike draws through Core Animation, not Metal: one `CGImage` per frame set as the layer's
/// contents. Metal with one reused texture is the plan for v1 once frame rate is measured.
@MainActor
final class ScreenView: NSView {
    enum PointerPhase {
        case down
        case dragged
        case up
        /// The pointer left the view; only matters while pressed.
        case exited
    }

    var onPointer: ((PointerPhase, CGPoint) -> Void)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    init(cornerRadius: CGFloat) {
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.backgroundColor = Theme.Palette.screenOff.cgColor
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .circular
        layer?.masksToBounds = true
        layer?.contentsGravity = .resize
        layer?.magnificationFilter = .linear
        layer?.minificationFilter = .linear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Shows a frame, or the off screen for nil.
    func show(_ image: CGImage?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contents = image
        CATransaction.commit()
    }

    /// Clicking the screen of an inactive window presses it, as in the iOS Simulator.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) { report(.down, event) }
    override func mouseDragged(with event: NSEvent) { report(.dragged, event) }
    override func mouseUp(with event: NSEvent) { report(.up, event) }
    override func mouseExited(with event: NSEvent) { report(.exited, event) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(
            NSTrackingArea(
                rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    private func report(_ phase: PointerPhase, _ event: NSEvent) {
        onPointer?(phase, convert(event.locationInWindow, from: nil))
    }
}

/// Hosts the model's one `ScreenView` in SwiftUI.
struct ScreenRepresentable: NSViewRepresentable {
    let view: ScreenView

    func makeNSView(context: Context) -> ScreenView { view }
    func updateNSView(_ nsView: ScreenView, context: Context) {}
}

/// Turns a frame's RGBA bytes into a `CGImage` without copying them again.
enum FrameImage {
    static func make(_ frame: ScreenFrame) -> CGImage? {
        guard let provider = CGDataProvider(data: frame.pixels as CFData) else { return nil }
        let bitsPerComponent = 8
        return CGImage(
            width: frame.size.width, height: frame.size.height, bitsPerComponent: bitsPerComponent,
            bitsPerPixel: bitsPerComponent * ScreenFrame.bytesPerPixel,
            bytesPerRow: frame.size.width * ScreenFrame.bytesPerPixel,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
