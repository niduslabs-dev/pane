import AppKit
import Observation
import PaneCore
import os

/// The tools that take over the screen's pointer: while one is on, nothing reaches the device.
enum PaneTool: String, CaseIterable {
    case inspect
    case measure
    case pickColour

    var title: String {
        switch self {
        case .inspect: "Inspect Layout"
        case .measure: "Measure"
        case .pickColour: "Pick Colour"
        }
    }

    /// The line at the top of the screen while the tool is on.
    var hint: String {
        switch self {
        case .inspect: "Inspect Layout · Esc to exit"
        case .measure: "Measure · drag between two points"
        case .pickColour: "Pick Colour · click to copy"
        }
    }
}

/// State for Inspect Layout, Measure and Pick Colour. Points are the drawn screen's (y down,
/// origin at its top left); frames and measurements are device pixels of the screen as turned.
@MainActor
@Observable
final class ToolsModel {
    @ObservationIgnored weak var host: PaneModel?

    private(set) var active: PaneTool?
    var isActive: Bool { active != nil }

    /// The device's accessibility tree as last read, or nil before the first read.
    private(set) var tree: LayoutTree?
    private(set) var isReadingLayout = false
    /// Why the last read gave no tree, in one line.
    private(set) var layoutProblem: String?
    /// The view under the pointer, and the one a click pinned.
    private(set) var hovered: LayoutNode?
    private(set) var pinned: LayoutNode?
    var inspected: LayoutNode? { pinned ?? hovered }

    /// The line being or last dragged.
    private(set) var measurement: MeasuredLine?

    /// Where the pointer is over the screen, for the loupe.
    private(set) var hoverPoint: CGPoint?
    private(set) var colour: PickedColour?
    /// The pixels around the pointer, row by row.
    private(set) var loupe: [[PickedColour]] = []
    /// True for a moment after a click copied the hex.
    private(set) var copied = false

    @ObservationIgnored private var snapEdges: SnapEdges?
    @ObservationIgnored private var dragStart: CGPoint?
    /// The screen changed while a read was running, so its tree may already be stale.
    @ObservationIgnored private var readAgain = false
    @ObservationIgnored private var lastRead: ContinuousClock.Instant?
    /// How long to leave between reads while they keep returning the same tree.
    @ObservationIgnored private var unchangedBackoff: Duration = .zero
    @ObservationIgnored private var readTask: Task<Void, Never>?
    @ObservationIgnored private var settleTask: Task<Void, Never>?
    @ObservationIgnored private var copiedTask: Task<Void, Never>?
    @ObservationIgnored private var firstChange: ContinuousClock.Instant?
    @ObservationIgnored private var lastChange: ContinuousClock.Instant?
    @ObservationIgnored private let log = Logger(subsystem: "dev.niduslabs.pane", category: "tools")

    /// Maps the drawn screen to device pixels, or nil with no host.
    var scale: ScreenScale? {
        guard let host else { return nil }
        return ScreenScale(
            viewSize: host.layout.screenRect.size, deviceSize: host.deviceSize, quadrants: host.quadrants)
    }

    var density: DensityScale {
        DensityScale(density: host?.profile.density ?? Theme.Frame.fallbackDensity)
    }

    // MARK: Turning tools on and off

    /// Turns a tool on, or off when it is the one already on. Only one is on at a time.
    func toggle(_ tool: PaneTool) {
        if active == tool {
            deactivate()
        } else {
            activate(tool)
        }
    }

    func activate(_ tool: PaneTool) {
        guard let host, host.status == .live else { return }
        // Whatever the device was being told ends before the tool takes the pointer.
        host.releaseAll()
        reset()
        active = tool
        log.info("Tool on: \(tool.rawValue, privacy: .public)")
        // Measure reads the layout too, so a line can snap to view edges.
        if tool != .pickColour { readLayout() }
    }

    func deactivate() {
        guard active != nil else { return }
        log.info("Tool off")
        reset()
        active = nil
    }

    private func reset() {
        readTask?.cancel()
        settleTask?.cancel()
        copiedTask?.cancel()
        readTask = nil
        settleTask = nil
        readAgain = false
        lastRead = nil
        unchangedBackoff = .zero
        firstChange = nil
        lastChange = nil
        tree = nil
        snapEdges = nil
        isReadingLayout = false
        layoutProblem = nil
        hovered = nil
        pinned = nil
        measurement = nil
        dragStart = nil
        hoverPoint = nil
        colour = nil
        loupe = []
        copied = false
    }

    // MARK: Pointer

    /// The pointer moved over the screen, or left it (nil).
    func hover(at point: CGPoint?) {
        guard let active, let scale else { return }
        let inside = point.flatMap { CGRect(origin: .zero, size: scale.viewSize).contains($0) ? $0 : nil }
        hoverPoint = inside
        switch active {
        case .inspect:
            let node = inside.flatMap { tree?.node(at: scale.pixels($0)) }
            if node != hovered { hovered = node }
        case .pickColour:
            updateColour()
        case .measure:
            break
        }
    }

    /// A click or drag on the screen while a tool is on.
    func pointer(_ phase: ScreenView.PointerPhase, at point: CGPoint) {
        guard let active, let scale else { return }
        switch (active, phase) {
        case (.inspect, .down):
            let node = tree?.node(at: scale.pixels(point))
            // A click on the pinned view lets it go; any other click pins what is under it.
            pinned = node == pinned ? nil : node
        case (.measure, .down):
            let start = snapped(scale.pixels(point), in: scale)
            dragStart = start
            measurement = MeasuredLine(start: start, end: start)
        case (.measure, .dragged), (.measure, .up):
            guard let start = dragStart else { return }
            let end = MeasuredLine.snappedEnd(
                start: start, end: clamped(scale.pixels(point), to: scale.pixelSize),
                axisDegrees: Theme.Tools.axisSnapDegrees, edges: snapEdges, edgeDistance: edgeSnapPixels(in: scale))
            measurement = MeasuredLine(start: start, end: end)
            if phase == .up { dragStart = nil }
        case (.pickColour, .down):
            hoverPoint = point
            updateColour()
            copyColour()
        default:
            break
        }
    }

    private func snapped(_ point: CGPoint, in scale: ScreenScale) -> CGPoint {
        let inside = clamped(point, to: scale.pixelSize)
        return snapEdges?.snapped(inside, within: edgeSnapPixels(in: scale)) ?? inside
    }

    private func clamped(_ point: CGPoint, to size: CGSize) -> CGPoint {
        CGPoint(x: min(max(point.x, 0), size.width), y: min(max(point.y, 0), size.height))
    }

    private func edgeSnapPixels(in scale: ScreenScale) -> CGFloat {
        scale.viewSize.width > 0 ? Theme.Tools.edgeSnapPoints * scale.pixelSize.width / scale.viewSize.width : 0
    }

    // MARK: Layout

    /// A frame arrived: the screen changed. The layout is read again once it has been still
    /// for a moment (or has kept changing for a while), and the loupe follows at once.
    func screenChanged() {
        guard let active else { return }
        if active == .pickColour {
            updateColour()
            return
        }
        let now = ContinuousClock.now
        lastChange = now
        if firstChange == nil { firstChange = now }
        guard settleTask == nil else { return }
        settleTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let first = self.firstChange, let last = self.lastChange else { return }
                // A screen that keeps changing without its layout changing (a blinking cursor)
                // is read less and less often.
                let due = max(
                    min(last.advanced(by: Theme.Tools.refreshDebounce), first.advanced(by: Theme.Tools.refreshMaxWait)),
                    self.lastRead.map { $0.advanced(by: self.unchangedBackoff) } ?? first)
                if ContinuousClock.now >= due { break }
                try? await Task.sleep(until: due, clock: .continuous)
            }
            guard let self, !Task.isCancelled else { return }
            self.settleTask = nil
            self.firstChange = nil
            self.lastChange = nil
            self.readLayout()
        }
    }

    /// Reads the accessibility tree with `uiautomator dump`. One read runs at a time; a change
    /// during a read is picked up by the next settle.
    private func readLayout() {
        guard readTask == nil else {
            readAgain = true
            return
        }
        guard let emulator = host?.emulator else { return }
        guard let adb = Adb(emulator: emulator) else {
            layoutProblem = "adb not found."
            return
        }
        readAgain = false
        isReadingLayout = true
        readTask = Task { [weak self] in
            var result: Result<LayoutTree, ToolProblem>
            do {
                let output = try await adb.run(LayoutTree.dumpArguments, timeout: Theme.Tools.dumpTimeout)
                result = .success(try LayoutTree.parse(output.text))
            } catch let failure as Adb.Failure {
                result = .failure(ToolProblem(message: failure.message))
            } catch {
                result = .failure(ToolProblem(message: "Couldn't read the layout."))
            }
            guard let self, !Task.isCancelled else { return }
            self.readTask = nil
            self.isReadingLayout = false
            self.lastRead = ContinuousClock.now
            switch result {
            case .success(let tree):
                self.log.info("Layout read: \(tree.frames.count) views")
                if tree == self.tree {
                    self.unchangedBackoff = min(
                        max(self.unchangedBackoff * 2, Theme.Tools.unchangedBackoffStart),
                        Theme.Tools.unchangedBackoffMax)
                } else {
                    self.unchangedBackoff = .zero
                }
                self.apply(tree)
            case .failure(let problem):
                self.log.error("Layout read failed: \(problem.message, privacy: .public)")
                // An older tree stays usable; with none, say why.
                if self.tree == nil { self.layoutProblem = problem.message }
            }
            // A change during the read goes through the settle wait again, not straight back in.
            if self.readAgain {
                self.readAgain = false
                self.screenChanged()
            }
        }
    }

    private struct ToolProblem: Error {
        var message: String
    }

    private func apply(_ tree: LayoutTree) {
        guard tree != self.tree else { return }
        self.tree = tree
        layoutProblem = nil
        snapEdges = SnapEdges(frames: tree.frames)
        // A pinned view that is still there (same frame and identity) stays pinned.
        if let pinned, !tree.contains(pinned) { self.pinned = nil }
        if let scale, let point = hoverPoint {
            hovered = tree.node(at: scale.pixels(point))
        } else {
            hovered = nil
        }
    }

    // MARK: Colour

    private func updateColour() {
        guard let point = hoverPoint, let scale, let image = host?.screenView.latestImage,
            let grid = PixelGrid(image: image)
        else {
            colour = nil
            loupe = []
            return
        }
        let pixel = grid.pixel(at: point, viewSize: scale.viewSize)
        let next = grid.colour(x: pixel.x, y: pixel.y)
        if next != colour { colour = next }
        let around = grid.neighbourhood(x: pixel.x, y: pixel.y, radius: Theme.Tools.loupeRadius)
        if around != loupe { loupe = around }
    }

    /// Puts the hex on the Mac's clipboard and shows "Copied." for a moment.
    private func copyColour() {
        guard let colour, let host else { return }
        let pasteboard = PaneModel.pasteboard
        pasteboard.clearContents()
        pasteboard.setString(colour.hex, forType: .string)
        host.noteOwnPasteboardWrite()
        log.info("Copied a colour")
        copied = true
        copiedTask?.cancel()
        copiedTask = Task { [weak self] in
            try? await Task.sleep(for: Theme.Tools.copiedDuration)
            guard let self, !Task.isCancelled else { return }
            self.copied = false
        }
    }
}

extension LayoutTree {
    /// Whether the tree still holds this exact view.
    func contains(_ node: LayoutNode) -> Bool {
        func search(_ nodes: [LayoutNode]) -> Bool {
            nodes.contains { candidate in
                (candidate.frame == node.frame && candidate.className == node.className
                    && candidate.resourceID == node.resourceID && candidate.text == node.text)
                    || search(candidate.children)
            }
        }
        return search(roots)
    }
}
