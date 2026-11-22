import AppKit
import CoreImage
import PaneCore
import SwiftUI

/// The emulator's screen: a layer-backed view whose layer shows the latest frame's IOSurface,
/// clipped to the screen's rounded corners, and which reports the pointer in its own
/// coordinates (y down).
///
/// Core Animation reads the pooled surface directly (`StreamFrame`), so a frame is copied once,
/// from the gRPC message into the surface, and never converted again on the main thread.
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
    /// A scroll at a point: deltas in points, and the trackpad phase (nil for a mouse wheel,
    /// whose deltas are lines). Momentum events are dropped: Android flings by itself.
    var onScroll: ((CGPoint, CGFloat, CGFloat, ScrollGesture.Phase?) -> Void)?
    /// A key down or up while the window is key. Returns false to let AppKit handle it
    /// (menu shortcuts).
    var onKey: ((NSEvent, Bool) -> Bool)?

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
        layerUsesCoreImageFilters = true
        veilLayer.opacity = 0
        layer?.addSublayer(veilLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The frame on screen now, for Pick Colour. Holding it also keeps its buffer out of the
    /// pool while the layer shows it.
    private(set) var latestFrame: StreamFrame?
    /// Command-V through the Edit menu.
    var onPaste: (() -> Void)?

    @objc func paste(_ sender: Any?) { onPaste?() }

    /// Shows a frame, or the off screen for nil.
    func show(_ frame: StreamFrame?) {
        latestFrame = frame
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contents = frame?.surface
        CATransaction.commit()
    }

    // MARK: The reshape's veil (board 27)

    /// The dim over the last frame while the screen changes shape.
    private let veilLayer = CALayer()
    private(set) var isVeiled = false
    private static let blurName = "veilBlur"
    private static let blurRadiusPath = "filters.\(blurName).\(kCIInputRadiusKey)"

    /// Veils the frame on screen: blurred, dimmed, and filling the screen cropped and centred
    /// while the screen morphs. Fades in; a second call keeps the veil up.
    func beginVeil() {
        guard let layer, !isVeiled else { return }
        isVeiled = true
        let radius = Theme.Reshape.blur * layer.contentsScale
        let blur = CIFilter(name: "CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
        blur?.name = Self.blurName
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.removeAllAnimations()
        veilLayer.removeAllAnimations()
        layer.contentsGravity = .resizeAspectFill
        layer.filters = blur.map { [$0] }
        veilLayer.backgroundColor = resolved(Theme.Reshape.scrim)
        veilLayer.opacity = 1
        CATransaction.commit()
        fade(layer, keyPath: Self.blurRadiusPath, from: 0, to: radius)
        fade(veilLayer, keyPath: "opacity", from: 0, to: 1)
    }

    /// Shows `frame` and clears the veil: the blur and dim ease out, or under Reduce Motion the
    /// new frame crossfades over the veiled one. `completion` runs once it has cleared.
    func clearVeil(showing frame: StreamFrame?, crossfade: Bool, completion: @escaping @MainActor () -> Void) {
        guard let layer, isVeiled else {
            show(frame)
            completion()
            return
        }
        isVeiled = false
        let radius = Theme.Reshape.blur * layer.contentsScale
        CATransaction.begin()
        CATransaction.setCompletionBlock { MainActor.assumeIsolated { completion() } }
        if crossfade {
            let transition = CATransition()
            transition.type = .fade
            transition.duration = Theme.Reshape.fadeDuration
            layer.add(transition, forKey: kCATransition)
            CATransaction.setDisableActions(true)
            latestFrame = frame
            layer.contents = frame?.surface
            layer.contentsGravity = .resize
            layer.filters = nil
            veilLayer.opacity = 0
        } else {
            CATransaction.setDisableActions(true)
            latestFrame = frame
            layer.contents = frame?.surface
            layer.contentsGravity = .resize
            veilLayer.opacity = 0
            layer.setValue(0, forKeyPath: Self.blurRadiusPath)
            fade(layer, keyPath: Self.blurRadiusPath, from: radius, to: 0)
            fade(veilLayer, keyPath: "opacity", from: 1, to: 0)
        }
        CATransaction.commit()
    }

    /// Drops the veil at once (the connection ended).
    func removeVeil() {
        guard let layer, isVeiled else { return }
        isVeiled = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.removeAllAnimations()
        veilLayer.removeAllAnimations()
        layer.filters = nil
        layer.contentsGravity = .resize
        veilLayer.opacity = 0
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        veilLayer.frame = bounds
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        veilLayer.backgroundColor = resolved(Theme.Reshape.scrim)
    }

    private func resolved(_ colour: NSColor) -> CGColor {
        var cgColor = colour.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance { cgColor = colour.cgColor }
        return cgColor
    }

    private func fade(_ target: CALayer, keyPath: String, from: CGFloat, to: CGFloat) {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.duration = Theme.Reshape.fadeDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        target.add(animation, forKey: keyPath)
    }

    /// Clicking the screen of an inactive window presses it, as in the iOS Simulator.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) { report(.down, event) }
    override func mouseDragged(with event: NSEvent) { report(.dragged, event) }
    override func mouseUp(with event: NSEvent) { report(.up, event) }
    override func mouseExited(with event: NSEvent) { report(.exited, event) }

    override func scrollWheel(with event: NSEvent) {
        guard event.momentumPhase.isEmpty else { return }
        let point = convert(event.locationInWindow, from: nil)
        let phase: ScrollGesture.Phase?
        if event.phase.contains(.began) {
            phase = .began
        } else if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            phase = .ended
        } else if event.phase.contains(.changed) {
            phase = .changed
        } else if event.hasPreciseScrollingDeltas {
            // A precise device without phases (some mice): treat it like a wheel, in points.
            phase = .wheel
        } else {
            phase = nil
        }
        onScroll?(point, event.scrollingDeltaX, event.scrollingDeltaY, phase)
    }

    override func keyDown(with event: NSEvent) {
        if onKey?(event, true) != true { super.keyDown(with: event) }
    }

    override func keyUp(with event: NSEvent) {
        if onKey?(event, false) != true { super.keyUp(with: event) }
    }

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
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> ScreenView { view }
    func updateNSView(_ nsView: ScreenView, context: Context) { nsView.layer?.cornerRadius = cornerRadius }
}

/// A frame button's invisible hit area. AppKit, not a SwiftUI gesture, so the first click on an
/// inactive window presses the button (as in the iOS Simulator) instead of only focusing the
/// window. Pressed for as long as the mouse is down; an accessibility press is a short click.
@MainActor
final class FrameButtonHitView: NSView {
    var onPress: ((Bool) -> Void)?
    private var isPressed = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) { setPressed(true) }
    override func mouseUp(with event: NSEvent) { setPressed(false) }

    /// Called on focus loss too, through the model's `releaseAll`; this only guards repeats.
    private func setPressed(_ pressed: Bool) {
        guard pressed != isPressed else { return }
        isPressed = pressed
        onPress?(pressed)
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityPerformPress() -> Bool {
        setPressed(true)
        setPressed(false)
        return true
    }
}

struct FrameButtonHitArea: NSViewRepresentable {
    let label: String
    let onPress: (Bool) -> Void

    func makeNSView(context: Context) -> FrameButtonHitView { FrameButtonHitView() }

    func updateNSView(_ view: FrameButtonHitView, context: Context) {
        view.onPress = onPress
        view.toolTip = label
        view.setAccessibilityLabel(label)
    }
}
