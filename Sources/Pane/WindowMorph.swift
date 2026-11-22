import AppKit
import PaneCore
import SwiftUI
import os

/// Moves the window and the drawn device together from one layout to another on
/// `motion.spring.slideIn`, one display refresh at a time (board 27's reshape).
///
/// The same approach as `FrameSlide`: a display link steps a spring and sets the window's
/// frame. At each step the device frame is laid out part way (`DeviceFrameLayout.interpolated`)
/// and handed to `onStep` before the window takes the matching size, so the two are drawn in
/// the same transaction. The window keeps its top edge and horizontal centre, moving only
/// to stay on its display. A new target while running starts from where the window is, so it
/// never jumps.
@MainActor
final class WindowMorph: NSObject {
    private weak var window: PaneWindow?
    private let from: DeviceFrameLayout
    private let to: DeviceFrameLayout
    private let startFrame: NSRect
    private let targetFrame: NSRect
    private let onStep: (DeviceFrameLayout) -> Void
    private let onSettled: () -> Void
    private let spring = Spring(response: Theme.Reshape.springResponse, dampingRatio: Theme.Reshape.springDamping)
    private var link: CADisplayLink?
    private var startTime: CFTimeInterval = 0
    /// The display refreshes the morph stepped on and the longest gap between two, for the
    /// smoothness check (logged when it settles).
    private var lastStep: CFTimeInterval = 0
    private var longestStep: CFTimeInterval = 0
    private var steps = 0
    /// Steps whose work wasn't done by the refresh they were for (a dropped frame).
    private var lateSteps = 0
    private let log = Logger(subsystem: "dev.niduslabs.pane", category: "morph")
    private(set) var current: DeviceFrameLayout

    init(
        window: PaneWindow, from: DeviceFrameLayout, to: DeviceFrameLayout,
        onStep: @escaping (DeviceFrameLayout) -> Void, onSettled: @escaping () -> Void
    ) {
        self.window = window
        self.from = from
        self.to = to
        self.onStep = onStep
        self.onSettled = onSettled
        current = from
        startFrame = window.frame
        targetFrame = window.frameKeepingTop(forContentSize: to.windowContentSize, from: window.frame)
    }

    var isRunning: Bool { link != nil }

    func start() {
        startTime = CACurrentMediaTime()
        let link = window?.displayLink(target: self, selector: #selector(step(_:)))
        if let fastest = window?.screen?.maximumFramesPerSecond {
            let rate = Float(fastest)
            link?.preferredFrameRateRange = CAFrameRateRange(minimum: rate, maximum: rate, preferred: rate)
        }
        link?.add(to: .main, forMode: .common)
        self.link = link
        if link == nil { finish() }
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        let elapsed = now - startTime
        if lastStep > 0 { longestStep = max(longestStep, link.timestamp - lastStep) }
        lastStep = link.timestamp
        steps += 1
        defer { if CACurrentMediaTime() > link.targetTimestamp { lateSteps += 1 } }
        if elapsed >= spring.settlingDuration(target: 1.0, epsilon: Theme.Reshape.settleEpsilon) {
            finish()
            return
        }
        let progress = CGFloat(spring.value(target: 1.0, time: elapsed))
        let layout = DeviceFrameLayout.interpolated(from: from, to: to, progress: progress)
        current = layout
        onStep(layout)
        window?.setFrame(frame(at: min(max(progress, 0), 1), layout: layout), display: true)
    }

    private func finish() {
        stop()
        log.info(
            "Morph settled: \(self.steps) steps over \((CACurrentMediaTime() - self.startTime) * 1000, format: .fixed(precision: 1)) ms, longest refresh gap \(self.longestStep * 1000, format: .fixed(precision: 2)) ms, \(self.lateSteps) late"
        )
        current = to
        onStep(to)
        window?.setFrame(targetFrame, display: true)
        onSettled()
    }

    /// The window frame for a step: the content size of the part-way layout, with the top edge
    /// and the centre moving from where they were to where the target puts them.
    private func frame(at progress: CGFloat, layout: DeviceFrameLayout) -> NSRect {
        guard let window else { return targetFrame }
        let size = window.frameRect(forContentRect: NSRect(origin: .zero, size: layout.windowContentSize)).size
        let midX = startFrame.midX + (targetFrame.midX - startFrame.midX) * progress
        let top = startFrame.maxY + (targetFrame.maxY - startFrame.maxY) * progress
        return NSRect(x: midX - size.width / 2, y: top - size.height, width: size.width, height: size.height)
    }
}

extension PaneWindow {
    /// The frame for a new content size with the top edge and horizontal centre of `frame`
    /// kept, moved only as far as needed to stay on the window's display. The centre is the one
    /// the last reshape asked for while the window is within rounding of it (`HeldCentre`);
    /// callers place the returned frame.
    func frameKeepingTop(forContentSize size: CGSize, from frame: NSRect) -> NSRect {
        let newFrame = frameRect(forContentRect: NSRect(origin: .zero, size: size))
        let centre = heldCentre.centre(for: frame)
        heldCentre.placed(at: centre)
        var origin = CGPoint(x: centre - newFrame.width / 2, y: frame.maxY - newFrame.height)
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX), visible.maxX - newFrame.width)
            origin.y = min(max(origin.y, visible.minY), visible.maxY - newFrame.height)
        }
        return NSRect(origin: origin, size: newFrame.size)
    }
}
