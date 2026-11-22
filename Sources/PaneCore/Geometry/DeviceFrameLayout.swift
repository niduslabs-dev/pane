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

/// Where one button sits on the body in the device's natural orientation: on `edge`, `offset`
/// design points from its `end` (a neighbouring side), `length` long. Points are at the
/// reference screen height and scale with the frame.
public struct FrameButtonSpec: Sendable, Equatable {
    public var button: FrameButton
    /// The side of the body the button sticks out of.
    public var edge: FrameEdge
    /// The end of that edge the offset is measured from: `.top` or `.bottom` for a side edge,
    /// `.left` or `.right` for the top or bottom edge.
    public var end: FrameEdge
    /// Distance from that end of the body to the near end of the visible button.
    public var offset: CGFloat
    public var length: CGFloat

    public init(button: FrameButton, edge: FrameEdge = .right, end: FrameEdge = .top, offset: CGFloat, length: CGFloat)
    {
        self.button = button
        self.edge = edge
        self.end = end
        self.offset = offset
        self.length = length
    }

    /// The same button on another edge, measured from another end.
    public func placed(on edge: FrameEdge, from end: FrameEdge) -> FrameButtonSpec {
        FrameButtonSpec(button: button, edge: edge, end: end, offset: offset, length: length)
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
        screenRadius: CGFloat, buttons: [FrameButtonSpec],
        buttonDepth: CGFloat, buttonHitDepth: CGFloat, buttonHitOutset: CGFloat, titleRowHeight: CGFloat,
        contentInset: CGFloat, bottomInset: CGFloat
    ) {
        self.screenHeight = screenHeight
        self.referenceScreenHeight = referenceScreenHeight
        self.bezel = bezel
        self.bodyRadius = bodyRadius
        self.screenRadius = screenRadius
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

    /// A button's two outer corners on `edge`: the one towards `end`, then the far one.
    static func outer(of edge: FrameEdge, from end: FrameEdge) -> (near: FrameCorners, far: FrameCorners) {
        let corners: (FrameCorners, FrameCorners) =
            switch edge {
            case .right: (.topRight, .bottomRight)
            case .left: (.topLeft, .bottomLeft)
            case .top: (.topLeft, .topRight)
            case .bottom: (.bottomLeft, .bottomRight)
            }
        let startsFromFirst = end == .top || end == .left
        return startsFromFirst ? (corners.0, corners.1) : (corners.1, corners.0)
    }

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
/// The screen's height in the device's natural orientation is `screenHeight` points; bezel,
/// radii and button positions scale with it from the spec's reference height, while hairlines,
/// button depth and hit areas stay put. Each button sits on its spec's edge, measured from its
/// end (board 28: a phone's on the right from the top, a tablet's on the top from the right).
/// `quadrants` turns the device counter-clockwise from its natural orientation, as the
/// emulator's `Rotation` reports it, and the buttons turn with the body.
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
        let portraitButtons = Self.placeButtons(spec.buttons, on: body, scale: scale, spec: spec)

        // Turn counter-clockwise a quarter at a time; the body stays at the origin.
        var bodySize = body.size
        var screenRect = screen
        var turnedButtons = portraitButtons
        for _ in 0..<turns {
            let turn = { (rect: CGRect) in
                CGRect(x: rect.minY, y: bodySize.width - rect.maxX, width: rect.height, height: rect.width)
            }
            screenRect = turn(screenRect)
            turnedButtons = turnedButtons.map { button in
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
        let edge = turnedButtons.first?.edge ?? .right
        let horizontal = spec.contentInset + (edge == .left || edge == .right ? spec.buttonDepth : 0)
        let top = spec.titleRowHeight + (edge == .top ? spec.buttonDepth : 0)
        let bottom = spec.bottomInset + (edge == .bottom ? spec.buttonDepth : 0)
        let origin = CGPoint(x: horizontal, y: top)
        let move = { (rect: CGRect) in rect.offsetBy(dx: origin.x, dy: origin.y) }

        self.quadrants = turns
        self.screenHeight = height
        bodyRect = CGRect(origin: origin, size: bodySize)
        self.screenRect = move(screenRect)
        bodyRadius = spec.bodyRadius * scale
        screenRadius = spec.screenRadius * scale
        buttons = turnedButtons.map { button in
            Button(
                button: button.button, visibleRect: move(button.visibleRect), hitRect: move(button.hitRect),
                edge: button.edge, roundedCorners: button.roundedCorners)
        }
        windowContentSize = CGSize(width: bodySize.width + 2 * horizontal, height: top + bodySize.height + bottom)
    }

    /// Lays the buttons out on the untouched body (origin at zero). Along each edge, the hit areas
    /// reach `buttonHitOutset` past each end, split evenly where neighbours are closer; a button
    /// touching a neighbour loses its rounded corner there (the volume rocker's seam).
    static func placeButtons(_ specs: [FrameButtonSpec], on body: CGRect, scale: CGFloat, spec: FrameSpec) -> [Button] {
        // Along the edge, measured from each button's own end.
        let along = specs.map { button in (start: button.offset * scale, end: (button.offset + button.length) * scale) }
        return specs.enumerated().map { index, button in
            let mine = along[index]
            var start = mine.start - spec.buttonHitOutset
            var end = mine.end + spec.buttonHitOutset
            var nearCorner = true
            var farCorner = true
            for (other, theirs) in along.enumerated()
            where other != index && specs[other].edge == button.edge && specs[other].end == button.end {
                if theirs.end <= mine.start, theirs.end + spec.buttonHitOutset > start {
                    start = max(start, (theirs.end + mine.start) / 2)
                }
                if theirs.start >= mine.end, theirs.start - spec.buttonHitOutset < end {
                    end = min(end, (theirs.start + mine.end) / 2)
                }
                if theirs.end == mine.start { nearCorner = false }
                if theirs.start == mine.end { farCorner = false }
            }
            let corners = FrameCorners.outer(of: button.edge, from: button.end)
            var rounded: FrameCorners = []
            if nearCorner { rounded.insert(corners.near) }
            if farCorner { rounded.insert(corners.far) }
            return Button(
                button: button.button,
                visibleRect: rect(
                    on: body, edge: button.edge, end: button.end, from: mine.start, to: mine.end,
                    depth: spec.buttonDepth),
                hitRect: rect(
                    on: body, edge: button.edge, end: button.end, from: start, to: end,
                    depth: spec.buttonHitDepth),
                edge: button.edge, roundedCorners: rounded)
        }
    }

    /// A strip `depth` deep outside `edge`, from `start` to `end` measured along it from `end`.
    private static func rect(
        on body: CGRect, edge: FrameEdge, end: FrameEdge, from start: CGFloat, to stop: CGFloat, depth: CGFloat
    ) -> CGRect {
        let length = stop - start
        let x = end == .right ? body.maxX - stop : body.minX + start
        let y = end == .bottom ? body.maxY - stop : body.minY + start
        switch edge {
        case .right: return CGRect(x: body.maxX, y: y, width: depth, height: length)
        case .left: return CGRect(x: body.minX - depth, y: y, width: depth, height: length)
        case .top: return CGRect(x: x, y: body.minY - depth, width: length, height: depth)
        case .bottom: return CGRect(x: x, y: body.maxY, width: length, height: depth)
        }
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

    /// The smallest whole-point screen height, at least `floor`, whose window is `minWidth` wide
    /// or wider. A tall, narrow device needs a taller screen than `floor` before its window is
    /// wide enough for the title and the menus drawn inside it; a wide one never does.
    public static func smallestScreenHeight(
        forWindowWidth minWidth: CGFloat, spec: FrameSpec, deviceSize: PixelSize, quadrants: Int, floor: CGFloat
    ) -> CGFloat {
        func width(_ height: CGFloat) -> CGFloat {
            DeviceFrameLayout(spec: spec, deviceSize: deviceSize, screenHeight: height, quadrants: quadrants)
                .windowContentSize.width
        }
        guard width(floor) < minWidth else { return floor }
        let reference = spec.referenceScreenHeight
        let slope = (width(2 * reference) - width(reference)) / reference
        guard slope > 0 else { return floor }
        var height = max(floor, ((minWidth - width(floor)) / slope + floor).rounded(.up))
        // The screen's short side is rounded to whole points, so step past any shortfall.
        while width(height) < minWidth { height += 1 }
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

    /// The buttons in VoiceOver's reading order: top to bottom on a side edge, left to right on
    /// the top or bottom edge (board 28).
    public var buttonsInReadingOrder: [Button] {
        buttons.sorted { a, b in
            (a.visibleRect.minY, a.visibleRect.minX) < (b.visibleRect.minY, b.visibleRect.minX)
        }
    }

    /// The button whose hit area contains a point in window coordinates.
    public func button(at point: CGPoint) -> FrameButton? {
        buttons.first { $0.hitRect.contains(point) }?.button
    }
}
