import CoreGraphics
import Foundation

/// One view from the device's accessibility tree, with its frame in device pixels of the
/// screen as it is turned now.
public struct LayoutNode: Sendable, Equatable {
    public var className: String
    public var text: String
    public var contentDescription: String
    public var resourceID: String
    public var frame: CGRect
    public var children: [LayoutNode]

    public init(
        className: String = "", text: String = "", contentDescription: String = "", resourceID: String = "",
        frame: CGRect, children: [LayoutNode] = []
    ) {
        self.className = className
        self.text = text
        self.contentDescription = contentDescription
        self.resourceID = resourceID
        self.frame = frame
        self.children = children
    }

    /// The class without its package: `android.widget.Button` reads "Button".
    public var shortClassName: String {
        className.split(whereSeparator: { $0 == "." || $0 == "$" }).last.map(String.init) ?? className
    }

    /// What the view says: its text, else its accessibility description, else nil.
    public var label: String? {
        if !text.isEmpty { return text }
        if !contentDescription.isEmpty { return contentDescription }
        return nil
    }
}

/// The accessibility tree `uiautomator dump` prints, and the questions Inspect Layout asks it.
public struct LayoutTree: Sendable, Equatable {
    public var roots: [LayoutNode]

    public init(roots: [LayoutNode]) {
        self.roots = roots
    }

    public static let dumpArguments = ["exec-out", "uiautomator", "dump", "/dev/tty"]

    public enum ParseError: Error, Equatable, Sendable {
        /// The output has no `<hierarchy>` (uiautomator's own error text, usually).
        case noHierarchy(String)
        case malformed
    }

    /// Parses the dump. Whatever uiautomator prints around the XML ("UI hierchary dumped to:
    /// /dev/tty") is ignored; nodes without readable bounds are dropped with their children.
    public static func parse(_ dump: String) throws(ParseError) -> LayoutTree {
        guard let start = dump.range(of: "<hierarchy"), let end = dump.range(of: "</hierarchy>", options: .backwards),
            start.lowerBound < end.upperBound
        else {
            throw .noHierarchy(Adb.shortReason(from: dump))
        }
        let builder = Builder()
        let parser = XMLParser(data: Data(dump[start.lowerBound..<end.upperBound].utf8))
        parser.delegate = builder
        guard parser.parse() else { throw .malformed }
        return LayoutTree(roots: builder.roots)
    }

    /// `[left,top][right,bottom]` as a rect, or nil.
    public static func frame(fromBounds bounds: String) -> CGRect? {
        let numbers = bounds.split(whereSeparator: { "[], ".contains($0) }).compactMap { Double($0) }
        let cornerValues = 4
        guard numbers.count == cornerValues, numbers[2] >= numbers[0], numbers[3] >= numbers[1] else { return nil }
        return CGRect(x: numbers[0], y: numbers[1], width: numbers[2] - numbers[0], height: numbers[3] - numbers[1])
    }

    /// The deepest view under a point: where views overlap, the one drawn last (the later
    /// sibling) wins. Nil when the point is over no view.
    public func node(at point: CGPoint) -> LayoutNode? {
        func find(in nodes: [LayoutNode]) -> LayoutNode? {
            for node in nodes.reversed() where Self.contains(node.frame, point) {
                return find(in: node.children) ?? node
            }
            // A child can be drawn outside its parent's frame.
            for node in nodes.reversed() {
                if let inner = find(in: node.children) { return inner }
            }
            return nil
        }
        return find(in: roots)
    }

    /// The deepest view under a point together with its parent's frame (nil for a root view,
    /// whose parent is the screen), for the distances Inspect shows once a view is pinned.
    public func hit(at point: CGPoint) -> (node: LayoutNode, parentFrame: CGRect?)? {
        func find(in nodes: [LayoutNode], parent: CGRect?) -> (LayoutNode, CGRect?)? {
            for node in nodes.reversed() where Self.contains(node.frame, point) {
                return find(in: node.children, parent: node.frame) ?? (node, parent)
            }
            for node in nodes.reversed() {
                if let inner = find(in: node.children, parent: node.frame) { return inner }
            }
            return nil
        }
        return find(in: roots, parent: nil)
    }

    /// Every view's frame, for snapping a measurement to edges.
    public var frames: [CGRect] {
        var all: [CGRect] = []
        func collect(_ nodes: [LayoutNode]) {
            for node in nodes {
                all.append(node.frame)
                collect(node.children)
            }
        }
        collect(roots)
        return all
    }

    private static func contains(_ frame: CGRect, _ point: CGPoint) -> Bool {
        frame.width > 0 && frame.height > 0 && point.x >= frame.minX && point.x < frame.maxX && point.y >= frame.minY
            && point.y < frame.maxY
    }

    private final class Builder: NSObject, XMLParserDelegate {
        var roots: [LayoutNode] = []
        /// Open nodes; nil stands for a dropped node, whose children are dropped too.
        private var stack: [LayoutNode?] = []

        func parser(
            _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
            qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]
        ) {
            guard elementName == "node" else { return }
            let parentDropped = stack.last.map { $0 == nil } ?? false
            guard !parentDropped, let frame = attributeDict["bounds"].flatMap(LayoutTree.frame(fromBounds:)) else {
                stack.append(nil)
                return
            }
            stack.append(
                LayoutNode(
                    className: attributeDict["class"] ?? "", text: attributeDict["text"] ?? "",
                    contentDescription: attributeDict["content-desc"] ?? "",
                    resourceID: attributeDict["resource-id"] ?? "", frame: frame))
        }

        func parser(
            _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?
        ) {
            guard elementName == "node", let closed = stack.popLast(), let node = closed else { return }
            if let parentIndex = stack.indices.last, stack[parentIndex] != nil {
                stack[parentIndex]?.children.append(node)
            } else if stack.isEmpty {
                roots.append(node)
            }
        }
    }
}

/// Device pixels to Android's density-independent pixels: `dp = px × 160 / density`.
public struct DensityScale: Sendable, Equatable {
    /// Android's baseline density, where 1 dp is 1 px.
    public static let baseline: CGFloat = 160

    public var density: CGFloat

    public init(density: Int) {
        self.density = CGFloat(max(density, 1))
    }

    public func dp(_ pixels: CGFloat) -> CGFloat { pixels * Self.baseline / density }

    /// Whole dp, rounded half away from zero, as layout tools show them.
    public func wholeDp(_ pixels: CGFloat) -> Int { Int(dp(pixels).rounded()) }

    /// "379 × 69 dp".
    public func sizeText(_ size: CGSize) -> String { "\(wholeDp(size.width)) × \(wholeDp(size.height)) dp" }

    /// "x 16, y 275, 379 × 69 dp".
    public func frameText(_ frame: CGRect) -> String {
        "x \(wholeDp(frame.minX)), y \(wholeDp(frame.minY)), \(sizeText(frame.size))"
    }

    /// "996 × 182 px".
    public static func pixelText(_ size: CGSize) -> String {
        "\(Int(size.width.rounded())) × \(Int(size.height.rounded())) px"
    }
}

/// How far a view is from the edges of the screen or of its parent, in device pixels.
public struct EdgeDistances: Sendable, Equatable {
    public var left: CGFloat
    public var top: CGFloat
    public var right: CGFloat
    public var bottom: CGFloat

    public init(frame: CGRect, screen: CGSize) {
        left = frame.minX
        top = frame.minY
        right = screen.width - frame.maxX
        bottom = screen.height - frame.maxY
    }

    /// How far a view is inside its parent on each side (never negative: a view that sticks
    /// out of its parent reads 0 there).
    public init(frame: CGRect, parent: CGRect) {
        left = max(0, frame.minX - parent.minX)
        top = max(0, frame.minY - parent.minY)
        right = max(0, parent.maxX - frame.maxX)
        bottom = max(0, parent.maxY - frame.maxY)
    }

    public enum Side: Sendable, Equatable {
        case left, top, right, bottom
    }

    /// The nearer of left and right (left on a tie), and how far it is.
    public var nearestHorizontal: (side: Side, distance: CGFloat) {
        left <= right ? (.left, left) : (.right, right)
    }

    /// The nearer of top and bottom (top on a tie), and how far it is.
    public var nearestVertical: (side: Side, distance: CGFloat) {
        top <= bottom ? (.top, top) : (.bottom, bottom)
    }
}

/// Maps between the drawn screen (view points, y down, origin at its top left) and the pixels
/// of the screen as it is turned now. Inspect, Measure and Pick Colour all work in that space.
public struct ScreenScale: Sendable, Equatable {
    public var viewSize: CGSize
    public var pixelSize: CGSize

    public init(viewSize: CGSize, pixelSize: CGSize) {
        self.viewSize = viewSize
        self.pixelSize = pixelSize
    }

    /// The size of the screen as shown: the device's size, sides swapped when turned a quarter.
    public init(viewSize: CGSize, deviceSize: PixelSize, quadrants: Int) {
        let shown = quadrants % 2 == 0 ? deviceSize : deviceSize.transposed
        self.init(viewSize: viewSize, pixelSize: CGSize(width: shown.width, height: shown.height))
    }

    public func pixels(_ point: CGPoint) -> CGPoint {
        guard viewSize.width > 0, viewSize.height > 0 else { return .zero }
        return CGPoint(
            x: point.x * pixelSize.width / viewSize.width, y: point.y * pixelSize.height / viewSize.height)
    }

    public func view(_ point: CGPoint) -> CGPoint {
        guard pixelSize.width > 0, pixelSize.height > 0 else { return .zero }
        return CGPoint(
            x: point.x * viewSize.width / pixelSize.width, y: point.y * viewSize.height / pixelSize.height)
    }

    public func view(_ rect: CGRect) -> CGRect {
        let origin = view(rect.origin)
        let far = view(CGPoint(x: rect.maxX, y: rect.maxY))
        return CGRect(x: origin.x, y: origin.y, width: far.x - origin.x, height: far.y - origin.y)
    }
}
