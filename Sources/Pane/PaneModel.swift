import AppKit
import Observation
import PaneCore
import os

/// The window's state: which emulator is shown, the connection to it, and the input rules
/// (every press ends in a release, even when the pointer leaves or the window loses focus).
@MainActor
@Observable
final class PaneModel {
    enum Status: Equatable {
        case noEmulator
        case connecting
        case live
        case failed(String)
    }

    private(set) var status: Status = .noEmulator
    private(set) var emulator: RunningEmulator?
    private(set) var profile = DeviceProfile()
    private(set) var layout = DeviceFrameLayout(spec: Theme.Frame.spec, deviceSize: Theme.Frame.fallbackDeviceSize)
    /// Frame buttons held down right now, so focus loss can release them.
    private(set) var heldButtons: Set<FrameButton> = []

    @ObservationIgnored let screenView = ScreenView(cornerRadius: Theme.Frame.screenRadius)
    @ObservationIgnored private var connection: EmulatorConnection?
    @ObservationIgnored private var connectionTask: Task<Void, Never>?
    @ObservationIgnored private var framesTask: Task<Void, Never>?
    @ObservationIgnored private var watcher: RegistrationWatcher?
    @ObservationIgnored private var pressedAt: DevicePoint?
    @ObservationIgnored private let log = Logger(subsystem: "dev.niduslabs.pane", category: "model")

    var title: String { emulator?.avdName ?? "Pane" }

    var meta: String {
        switch status {
        case .live, .connecting: profile.summary.isEmpty ? "Android emulator" : profile.summary
        case .failed: "Not connected"
        case .noEmulator: "Android emulator"
        }
    }

    var deviceSize: PixelSize { profile.screenSize ?? Theme.Frame.fallbackDeviceSize }

    init() {
        screenView.onPointer = { [weak self] phase, point in self?.handlePointer(phase, at: point) }
    }

    /// Starts watching for emulators and attaches to the first one running.
    func start() {
        let watcher = RegistrationWatcher { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        if !watcher.start() {
            log.info("No emulator registration folder yet")
        }
        self.watcher = watcher
        refresh()
    }

    /// Re-reads the registration folder: drops a gone emulator, attaches to a new one.
    func refresh() {
        let running = EmulatorDiscovery.runningEmulators()
        if let current = emulator, !running.contains(where: { $0.pid == current.pid }) {
            disconnect()
        }
        if emulator == nil, let first = running.first {
            connect(to: first)
        }
    }

    private func connect(to emulator: RunningEmulator) {
        self.emulator = emulator
        profile = emulator.avdDirectory.map(DeviceProfile.load(avdDirectory:)) ?? DeviceProfile()
        layout = DeviceFrameLayout(spec: Theme.Frame.spec, deviceSize: deviceSize)
        status = .connecting
        log.info(
            "Connecting to \(emulator.avdName, privacy: .public) on port \(emulator.grpcPort), version \(emulator.emulatorVersion ?? "?", privacy: .public)"
        )

        let connection: EmulatorConnection
        do {
            connection = try EmulatorConnection(emulator: emulator, deviceSize: deviceSize)
        } catch {
            status = .failed(String(describing: error))
            return
        }
        self.connection = connection
        connectionTask = Task {
            do {
                try await connection.run()
            } catch {
                self.log.error("Connection ended: \(String(describing: error), privacy: .public)")
                if self.connection === connection { self.status = .failed(String(describing: error)) }
            }
        }
        startFrames(on: connection)
    }

    private func startFrames(on connection: EmulatorConnection) {
        let backingScale = screenView.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        let size = ScreenMapping.requestedImageSize(
            screenPoints: layout.screenRect.size, backingScale: backingScale, deviceSize: deviceSize)
        let screenView = screenView
        log.info("Requesting frames at \(size.description, privacy: .public)")
        let log = log
        framesTask = Task.detached { [weak self] in
            var stats = FrameStats(intervalSeconds: Theme.Diagnostics.frameStatsInterval)
            do {
                for try await frame in connection.screenFrames(size: size) {
                    if let summary = stats.record(
                        sequence: frame.sequence, emulatorTimestamp: frame.timestampMicroseconds)
                    {
                        log.info(
                            "Frames: \(summary.frames) in window, \(summary.framesPerSecond, format: .fixed(precision: 1)) fps, \(summary.dropped) dropped, latency mean \(summary.meanLatencyMilliseconds, format: .fixed(precision: 1)) ms max \(summary.maxLatencyMilliseconds, format: .fixed(precision: 1)) ms, \(frame.size.description, privacy: .public)"
                        )
                    }
                    let image = FrameImage.make(frame)
                    await MainActor.run {
                        screenView.show(image)
                        if self?.status == .connecting { self?.status = .live }
                    }
                }
            } catch is CancellationError {
            } catch {
                await MainActor.run { self?.status = .failed(String(describing: error)) }
            }
        }
    }

    private func disconnect() {
        releaseAll()
        framesTask?.cancel()
        connectionTask?.cancel()
        connection?.shutdown()
        framesTask = nil
        connectionTask = nil
        connection = nil
        emulator = nil
        status = .noEmulator
        screenView.show(nil)
    }

    // MARK: Input

    private var mapping: ScreenMapping {
        ScreenMapping(
            screenRect: CGRect(origin: .zero, size: layout.screenRect.size), deviceSize: deviceSize)
    }

    private func handlePointer(_ phase: ScreenView.PointerPhase, at point: CGPoint) {
        log.debug("Pointer \(String(describing: phase), privacy: .public) at \(point.x), \(point.y)")
        guard let connection else { return }
        switch phase {
        case .down:
            guard let device = mapping.devicePoint(for: point) else { return }
            pressedAt = device
            connection.send(.press(device))
        case .dragged:
            guard pressedAt != nil else { return }
            if let device = mapping.devicePoint(for: point) {
                pressedAt = device
                connection.send(.press(device))
            } else {
                // Dragged off the screen: lift at the edge, as Android Studio does.
                connection.send(.release(mapping.clampedDevicePoint(for: point)))
                pressedAt = nil
            }
        case .up:
            guard pressedAt != nil else { return }
            connection.send(.release(mapping.clampedDevicePoint(for: point)))
            pressedAt = nil
        case .exited:
            releasePointer()
        }
    }

    private func releasePointer() {
        guard let point = pressedAt else { return }
        connection?.send(.release(point))
        pressedAt = nil
    }

    /// Presses or releases a frame button. Power is held for as long as the mouse is down, so a
    /// long press opens Android's power menu.
    func setButton(_ button: FrameButton, isDown: Bool) {
        guard let connection else { return }
        if isDown {
            guard heldButtons.insert(button).inserted else { return }
        } else {
            guard heldButtons.remove(button) != nil else { return }
        }
        log.debug("Key \(button.keyName, privacy: .public) \(isDown ? "down" : "up", privacy: .public)")
        connection.send(.key(name: button.keyName, isDown: isDown))
    }

    /// Lifts any held touch and key. Called on focus loss and app deactivation.
    func releaseAll() {
        releasePointer()
        for button in heldButtons { setButton(button, isDown: false) }
    }
}
