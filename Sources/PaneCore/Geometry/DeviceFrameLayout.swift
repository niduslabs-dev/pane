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
    /// The inset around the frame on the left and right; the title row is above.
    public var contentInset: CGFloat
    /// The band below the frame (the toolbar's).
    public var bottomInset: CGFloat

    public init(
        screenHeight: CGFloat, referenceScreenHeight: CGFloat, bezel: CGFloat, bodyRadius: CGFloat,
        screenRadius: CGFloat, punchHoleDiameter: CGFloat, punchHoleTop: CGFloat, buttons: [FrameButtonSpec],
        buttonDepth: CGFloat, buttonHitDepth: CGFloat, buttonHitOutset: CGFloat, titleRowHeight: CGFloat,
        contentInset: CGFloat, bottomInset: CGFloat
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
        self.bottomInset = bottomInset
    }
}

/// A side of the drawn device, after rotation.
public enum FrameEdge: Sendable, Equatable {
    case top
    case left
    case bottom
    case right

    /// The same side after the device turns a quarter counter-clockwise.
    var turnedCounterClockwise: FrameEdge {
        switch self {
        case .right: .top
        case .top: .left
        case .left: .bottom
        case .bottom: .right
        }
    }
}

/// Corners of a drawn button that are rounded.
public struct FrameCorners: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let topLeft = FrameCorners(rawValue: 1 << 0)
    public static let topRight = FrameCorners(rawValue: 1 << 1)
    public static let bottomLeft = FrameCorners(rawValue: 1 << 2)
    public static let bottomRight = FrameCorners(rawValue: 1 << 3)

    var turnedCounterClockwise: FrameCorners {
        var turned: FrameCorners = []
        if contains(.topRight) { turned.insert(.topLeft) }
        if contains(.topLeft) { turned.insert(.bottomLeft) }
        if contains(.bottomLeft) { turned.insert(.bottomRight) }
        if contains(.bottomRight) { turned.insert(.topRight) }
        return turned
    }
}

/// The frame laid out for one device, size and orientation: every rect in the window content's
/// coordinates (y down), plus the window content size around it.
///
/// The screen's long side is `screenHeight` points; bezel, radii, punch hole and button
/// positions scale with it from the spec's reference height, while hairlines, button depth and
/// hit areas stay put. `quadrants` turns the device counter-clockwise from portrait, as the
/// emulator's `Rotation` reports it, so the side buttons end up on the top (1), left (2) or
/// bottom (3) edge.
public struct DeviceFrameLayout: Sendable, Equatable {
    public struct Button: Sendable, Equatable {
        public var button: FrameButton
        /// The drawn button, outside the body's edge.
        public var visibleRect: CGRect
        /// Where a click presses it: wider and a little longer than what's drawn.
        public var hitRect: CGRect
        /// The side of the body the button sticks out of.
        public var edge: FrameEdge
        /// Its outer corners, except where it meets a neighbour (the volume rocker's seam).
        public var roundedCorners: FrameCorners

        /// The drawn button grown outwards to `depth`, for the hover state.
        public func visibleRect(depth: CGFloat) -> CGRect {
            let extra = depth - (edge == .left || edge == .right ? visibleRect.width : visibleRect.height)
            switch edge {
            case .right:
                return CGRect(x: visibleRect.minX, y: visibleRect.minY, width: depth, height: visibleRect.height)
            case .left:
                return CGRect(
                    x: visibleRect.minX - extra, y: visibleRect.minY, width: depth, height: visibleRect.height)
            case .bottom:
                return CGRect(x: visibleRect.minX, y: visibleRect.minY, width: visibleRect.width, height: depth)
            case .top:
                return CGRect(x: visibleRect.minX, y: visibleRect.minY - extra, width: visibleRect.width, height: depth)
            }
        }
    }

    public var quadrants: Int
    /// The screen's long side in points.
    public var screenHeight: CGFloat
    public var bodyRect: CGRect
    public var screenRect: CGRect
    public var punchHoleRect: CGRect
    public var bodyRadius: CGFloat
    public var screenRadius: CGFloat
    public var buttons: [Button]
    /// The window's content size: title row, frame, insets, and room for the buttons.
    public var windowContentSize: CGSize

    public init(spec: FrameSpec, deviceSize: PixelSize, screenHeight: CGFloat? = nil, quadrants: Int = 0) {
        let turns = ((quadrants % 4) + 4) % 4
        let height = screenHeight ?? spec.screenHeight
        let scale = spec.referenceScreenHeight > 0 ? height / spec.referenceScreenHeight : 1
        let aspect = deviceSize.height > 0 ? CGFloat(deviceSize.width) / CGFloat(deviceSize.height) : 0
        let bezel = spec.bezel * scale

        // Portrait, with the body's top left at the origin.
        let screenSize = CGSize(width: (height * aspect).rounded(), height: height)
        let body = CGRect(x: 0, y: 0, width: screenSize.width + 2 * bezel, height: screenSize.height + 2 * bezel)
        let screen = CGRect(origin: CGPoint(x: bezel, y: bezel), size: screenSize)
        let holeDiameter = spec.punchHoleDiameter * scale
        let hole = CGRect(
            x: screen.midX - holeDiameter / 2, y: screen.minY + spec.punchHoleTop * scale, width: holeDiameter,
            height: holeDiameter)
        let visible = spec.buttons.map { button in
            CGRect(x: body.maxX, y: button.top * scale, width: spec.buttonDepth, height: button.length * scale)
        }
        var portraitButtons = spec.buttons.enumerated().map { index, button in
            var top = visible[index].minY - spec.buttonHitOutset
            var bottom = visible[index].maxY + spec.buttonHitOutset
            var corners: FrameCorners = [.topRight, .bottomRight]
            for (other, rect) in visible.enumerated() where other != index {
                if rect.maxY <= visible[index].minY, rect.maxY + spec.buttonHitOutset > top {
                    top = max(top, (rect.maxY + visible[index].minY) / 2)
                }
                if rect.minY >= visible[index].maxY, rect.minY - spec.buttonHitOutset < bottom {
                    bottom = min(bottom, (rect.minY + visible[index].maxY) / 2)
                }
                if rect.maxY == visible[index].minY { corners.remove(.topRight) }
                if rect.minY == visible[index].maxY { corners.remove(.bottomRight) }
            }
            let hit = CGRect(x: body.maxX, y: top, width: spec.buttonHitDepth, height: bottom - top)
            return Button(
                button: button.button, visibleRect: visible[index], hitRect: hit, edge: .right, roundedCorners: corners)
        }

        // Turn counter-clockwise a quarter at a time; the body stays at the origin.
        var bodySize = body.size
        var screenRect = screen
        var holeRect = hole
        for _ in 0..<turns {
            let turn = { (rect: CGRect) in
                CGRect(x: rect.minY, y: bodySize.width - rect.maxX, width: rect.height, height: rect.width)
            }
            screenRect = turn(screenRect)
            holeRect = turn(holeRect)
            portraitButtons = portraitButtons.map { button in
                Button(
                    button: button.button, visibleRect: turn(button.visibleRect), hitRect: turn(button.hitRect),
                    edge: button.edge.turnedCounterClockwise,
                    roundedCorners: button.roundedCorners.turnedCounterClockwise)
            }
            bodySize = CGSize(width: bodySize.height, height: bodySize.width)
        }

        // Margins: the inset on the sides, the title row on top, the toolbar's band below, plus
        // the buttons' depth on
        // their side (both sides horizontally, so the body stays centred).
        let edge = portraitButtons.first?.edge ?? .right
        let horizontal = spec.contentInset + (edge == .left || edge == .right ? spec.buttonDepth : 0)
        let top = spec.titleRowHeight + (edge == .top ? spec.buttonDepth : 0)
        let bottom = spec.bottomInset + (edge == .bottom ? spec.buttonDepth : 0)
        let origin = CGPoint(x: horizontal, y: top)
        let move = { (rect: CGRect) in rect.offsetBy(dx: origin.x, dy: origin.y) }

        self.quadrants = turns
        self.screenHeight = height
        bodyRect = CGRect(origin: origin, size: bodySize)
        self.screenRect = move(screenRect)
        punchHoleRect = move(holeRect)
        bodyRadius = spec.bodyRadius * scale
        screenRadius = spec.screenRadius * scale
        buttons = portraitButtons.map { button in
            Button(
                button: button.button, visibleRect: move(button.visibleRect), hitRect: move(button.hitRect),
                edge: button.edge, roundedCorners: button.roundedCorners)
        }
        windowContentSize = CGSize(width: bodySize.width + 2 * horizontal, height: top + bodySize.height + bottom)
    }

    /// The largest whole-point screen height whose layout fits `contentSize`, within
    /// `range`. Used to keep the window at the device's shape while it is resized.
    public static func screenHeight(
        fitting contentSize: CGSize, spec: FrameSpec, deviceSize: PixelSize, quadrants: Int,
        range: ClosedRange<CGFloat>
    ) -> CGFloat {
        // Width and height grow linearly with the screen height; measure at two heights.
        let small = DeviceFrameLayout(
            spec: spec, deviceSize: deviceSize, screenHeight: spec.referenceScreenHeight, quadrants: quadrants)
        let large = DeviceFrameLayout(
            spec: spec, deviceSize: deviceSize, screenHeight: 2 * spec.referenceScreenHeight, quadrants: quadrants)
        let reference = spec.referenceScreenHeight
        let widthSlope = (large.windowContentSize.width - small.windowContentSize.width) / reference
        let heightSlope = (large.windowContentSize.height - small.windowContentSize.height) / reference
        let widthFixed = small.windowContentSize.width - widthSlope * reference
        let heightFixed = small.windowContentSize.height - heightSlope * reference
        var fit = range.upperBound
        if widthSlope > 0 { fit = min(fit, (contentSize.width - widthFixed) / widthSlope) }
        if heightSlope > 0 { fit = min(fit, (contentSize.height - heightFixed) / heightSlope) }
        var height = min(max(fit.rounded(.down), range.lowerBound), range.upperBound)
        // The screen's short side is rounded to whole points, which can overshoot by a fraction.
        while height > range.lowerBound {
            let size = DeviceFrameLayout(spec: spec, deviceSize: deviceSize, screenHeight: height, quadrants: quadrants)
                .windowContentSize
            if size.width <= contentSize.width, size.height <= contentSize.height { break }
            height -= 1
        }
        return height
    }

    /// The button nearest a point (window coordinates) within `distance` of its drawn outline,
    /// measured from any side, or nil. Only this one slides out, as in the iOS Simulator.
    public func nearestButton(to point: CGPoint, within distance: CGFloat) -> FrameButton? {
        let distances = buttons.map { button -> (FrameButton, CGFloat) in
            let rect = button.visibleRect
            let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
            let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
            return (button.button, (dx * dx + dy * dy).squareRoot())
        }
        guard let nearest = distances.min(by: { $0.1 < $1.1 }), nearest.1 <= distance else { return nil }
        return nearest.0
    }

    /// The button whose hit area contains a point in window coordinates.
    public func button(at point: CGPoint) -> FrameButton? {
        buttons.first { $0.hitRect.contains(point) }?.button
    }
}
