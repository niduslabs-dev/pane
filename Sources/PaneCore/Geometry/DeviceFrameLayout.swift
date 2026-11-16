import CoreGraphics

/// A hardware button on the drawn frame.
public enum FrameButton: String, Sendable, CaseIterable {
    case power
    case volumeUp
    case volumeDown

    /// The W3C key name the emulator's `KeyboardEvent.key` takes (as Android Studio sends).
    public var keyName: String {
        switch self {
        case .power: "Power"
        case .volumeUp: "AudioVolumeUp"
        case .volumeDown: "AudioVolumeDown"
        }
    }
}

/// Where one button sits on the right edge, in design points for the reference screen height.
public struct FrameButtonSpec: Sendable, Equatable {
    public var button: FrameButton
    /// Distance from the top of the frame body to the top of the visible button.
    public var top: CGFloat
    public var length: CGFloat

    public init(button: FrameButton, top: CGFloat, length: CGFloat) {
        self.button = button
        self.top = top
        self.length = length
    }
}

/// The frame's design values. The app's `Theme` supplies the real ones; nothing here is a default.
public struct FrameSpec: Sendable, Equatable {
    /// The drawn screen's height in points; its width follows the device's aspect ratio.
    public var screenHeight: CGFloat
    /// The screen height the button positions were designed at; they scale with `screenHeight`.
    public var referenceScreenHeight: CGFloat
    public var bezel: CGFloat
    public var bodyRadius: CGFloat
    public var screenRadius: CGFloat
    public var punchHoleDiameter: CGFloat
    /// From the top of the screen to the top of the punch hole.
    public var punchHoleTop: CGFloat
    public var buttons: [FrameButtonSpec]
    /// How far a button sticks out of the body.
    public var buttonDepth: CGFloat
    /// The width of a button's invisible hit area, measured out from the body's edge.
    public var buttonHitDepth: CGFloat
    /// How far the hit area reaches past each end of the button (split evenly between neighbours).
    public var buttonHitOutset: CGFloat
    public var titleRowHeight: CGFloat
    /// The inset around the frame on the left, right and bottom; the title row is above.
    public var contentInset: CGFloat

    public init(
        screenHeight: CGFloat, referenceScreenHeight: CGFloat, bezel: CGFloat, bodyRadius: CGFloat,
        screenRadius: CGFloat, punchHoleDiameter: CGFloat, punchHoleTop: CGFloat, buttons: [FrameButtonSpec],
        buttonDepth: CGFloat, buttonHitDepth: CGFloat, buttonHitOutset: CGFloat, titleRowHeight: CGFloat,
        contentInset: CGFloat
    ) {
        self.screenHeight = screenHeight
        self.referenceScreenHeight = referenceScreenHeight
        self.bezel = bezel
        self.bodyRadius = bodyRadius
        self.screenRadius = screenRadius
        self.punchHoleDiameter = punchHoleDiameter
        self.punchHoleTop = punchHoleTop
        self.buttons = buttons
        self.buttonDepth = buttonDepth
        self.buttonHitDepth = buttonHitDepth
        self.buttonHitOutset = buttonHitOutset
        self.titleRowHeight = titleRowHeight
        self.contentInset = contentInset
    }
}

/// The frame laid out for one device: every rect in the frame's own coordinates (origin at the
/// body's top left, y down), plus the window content size around it.
public struct DeviceFrameLayout: Sendable, Equatable {
    public struct Button: Sendable, Equatable {
        public var button: FrameButton
        /// The drawn button, outside the body's right edge.
        public var visibleRect: CGRect
        /// Where a click presses it: wider and a little taller than what's drawn.
        public var hitRect: CGRect
    }

    public var bodyRect: CGRect
    public var screenRect: CGRect
    public var punchHoleRect: CGRect
    public var buttons: [Button]
    /// The window's content size: title row, frame, insets, and room for the buttons.
    public var windowContentSize: CGSize
    /// Where the body sits in the window content (y down, below the title row).
    public var bodyOriginInWindow: CGPoint

    public init(spec: FrameSpec, deviceSize: PixelSize) {
        let aspect = deviceSize.height > 0 ? CGFloat(deviceSize.width) / CGFloat(deviceSize.height) : 0
        let screenSize = CGSize(width: (spec.screenHeight * aspect).rounded(), height: spec.screenHeight)
        let body = CGRect(
            x: 0, y: 0, width: screenSize.width + 2 * spec.bezel, height: screenSize.height + 2 * spec.bezel)
        bodyRect = body
        screenRect = CGRect(origin: CGPoint(x: spec.bezel, y: spec.bezel), size: screenSize)
        punchHoleRect = CGRect(
            x: screenRect.midX - spec.punchHoleDiameter / 2, y: screenRect.minY + spec.punchHoleTop,
            width: spec.punchHoleDiameter, height: spec.punchHoleDiameter)

        let scale = spec.referenceScreenHeight > 0 ? spec.screenHeight / spec.referenceScreenHeight : 1
        let visible = spec.buttons.map { button in
            CGRect(
                x: body.maxX, y: button.top * scale, width: spec.buttonDepth, height: button.length * scale)
        }
        buttons = spec.buttons.enumerated().map { index, button in
            var top = visible[index].minY - spec.buttonHitOutset
            var bottom = visible[index].maxY + spec.buttonHitOutset
            for (other, rect) in visible.enumerated() where other != index {
                if rect.maxY <= visible[index].minY, rect.maxY + spec.buttonHitOutset > top {
                    top = max(top, (rect.maxY + visible[index].minY) / 2)
                }
                if rect.minY >= visible[index].maxY, rect.minY - spec.buttonHitOutset < bottom {
                    bottom = min(bottom, (rect.minY + visible[index].maxY) / 2)
                }
            }
            let hit = CGRect(x: body.maxX, y: top, width: spec.buttonHitDepth, height: bottom - top)
            return Button(button: button.button, visibleRect: visible[index], hitRect: hit)
        }

        let sideMargin = spec.contentInset + spec.buttonDepth
        bodyOriginInWindow = CGPoint(x: sideMargin, y: spec.titleRowHeight)
        windowContentSize = CGSize(
            width: bodyRect.width + 2 * sideMargin,
            height: spec.titleRowHeight + bodyRect.height + spec.contentInset)
    }

    /// The button whose hit area contains a point in frame coordinates.
    public func button(at point: CGPoint) -> FrameButton? {
        buttons.first { $0.hitRect.contains(point) }?.button
    }
}
