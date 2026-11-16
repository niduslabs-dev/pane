import AppKit
import Observation
import PaneCore
import os

/// The window's state: which emulator is shown, the connection to it, the emulator Pane started
/// (if any), and the input rules (every press ends in a release, even when the pointer leaves or
/// the window loses focus).
@MainActor
@Observable
final class PaneModel {
    enum Status: Equatable {
        /// Nothing running: the screen offers Start (canvas option A).
        case noEmulator
        /// Pane launched an emulator and is waiting for it to register.
        case starting
        case connecting
        /// Connected, Android still booting.
        case booting
        case live
        /// Can't reach a running emulator (canvas error state).
        case failed
    }

    private(set) var status: Status = .noEmulator
    private(set) var emulator: RunningEmulator?
    private(set) var profile = DeviceProfile()
    private(set) var layout = DeviceFrameLayout(spec: Theme.Frame.spec, deviceSize: Theme.Frame.fallbackDeviceSize)
    /// Frame buttons held down right now, so focus loss can release them.
    private(set) var heldButtons: Set<FrameButton> = []
    /// The AVDs on disk, for Start and "Choose another emulator".
    private(set) var avds: [AvdInfo] = []
    /// Why the last Start didn't work, shown under the Start button.
    private(set) var startProblem: String?

    /// The AVD Start launches, remembered across launches.
    var selectedAVDName: String? {
        didSet { UserDefaults.standard.set(selectedAVDName, forKey: Self.selectedAVDKey) }
    }

    @ObservationIgnored let screenView = ScreenView(cornerRadius: Theme.Frame.screenRadius)
    @ObservationIgnored private var connection: EmulatorConnection?
    @ObservationIgnored private var connectionTask: Task<Void, Never>?
    @ObservationIgnored private var framesTask: Task<Void, Never>?
    @ObservationIgnored private var bootTask: Task<Void, Never>?
    @ObservationIgnored private var startTask: Task<Void, Never>?
    @ObservationIgnored private var watcher: RegistrationWatcher?
    @ObservationIgnored private var pressedAt: DevicePoint?
    /// The emulator process Pane launched, and the PID of the emulator it became once it
    /// registered. Pane only ever stops these without asking.
    @ObservationIgnored private var launchedProcess: Process?
    @ObservationIgnored private var ownedEmulatorPID: Int32?
    @ObservationIgnored private var hasFrame = false
    @ObservationIgnored private var isBooted = false
    @ObservationIgnored private let log = Logger(subsystem: "dev.niduslabs.pane", category: "model")

    private static let selectedAVDKey = "selectedAVD"

    var title: String {
        switch status {
        case .noEmulator: "Pane"
        case .starting: selectedAVD?.name ?? "Pane"
        case .connecting, .booting, .live, .failed: emulator?.avdName ?? "Pane"
        }
    }

    var meta: String {
        switch status {
        case .live, .connecting, .booting, .starting: profile.summary.isEmpty ? "Android emulator" : profile.summary
        case .failed: "Not connected"
        case .noEmulator: "Android emulator"
        }
    }

    var selectedAVD: AvdInfo? {
        avds.first { $0.name == selectedAVDName } ?? avds.first
    }

    /// True when the emulator on screen is one Pane started, so it may restart it unasked.
    var ownsEmulator: Bool {
        guard let emulator else { return false }
        return emulator.pid == ownedEmulatorPID
    }

    var deviceSize: PixelSize { profile.screenSize ?? Theme.Frame.fallbackDeviceSize }

    init() {
        selectedAVDName = UserDefaults.standard.string(forKey: Self.selectedAVDKey)
        screenView.onPointer = { [weak self] phase, point in self?.handlePointer(phase, at: point) }
    }

    /// Starts watching for emulators and attaches to the first one running.
    func start() {
        reloadAVDs()
        startWatcher()
        refresh()
    }

    func reloadAVDs() {
        avds = AvdCatalog.list()
        if status == .noEmulator, let avd = selectedAVD { profile = avd.profile }
    }

    func selectAVD(_ name: String) {
        selectedAVDName = name
        startProblem = nil
        if status == .noEmulator, let avd = selectedAVD { profile = avd.profile }
    }

    private func startWatcher() {
        guard watcher == nil else { return }
        let watcher = RegistrationWatcher { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        if watcher.start() {
            self.watcher = watcher
        } else {
            log.info("No emulator registration folder yet")
        }
    }

    /// Re-reads the registration folder: drops a gone emulator, attaches to a new one (the
    /// selected AVD's first, else any).
    func refresh() {
        let running = EmulatorDiscovery.runningEmulators()
        if let current = emulator, !running.contains(where: { $0.pid == current.pid }) {
            log.info("Emulator \(current.avdName, privacy: .public) is gone")
            disconnect()
            if ownedEmulatorPID == current.pid { ownedEmulatorPID = nil }
            if status != .starting { status = .noEmulator }
        }
        guard emulator == nil else { return }
        let wanted = status == .starting ? launchedAVDName : selectedAVDName
        if let next = running.first(where: { $0.avdName == wanted }) ?? (status == .starting ? nil : running.first) {
            connect(to: next)
        }
    }

    // MARK: Starting and restarting

    @ObservationIgnored private var launchedAVDName: String?

    /// Launches the selected AVD headless and shows its progress until it is live.
    func startSelectedEmulator() {
        reloadAVDs()
        guard let avd = selectedAVD else {
            startProblem = "No emulators set up."
            return
        }
        launch(avdName: avd.name, profile: avd.profile)
    }

    private func launch(avdName: String, profile: DeviceProfile) {
        guard let executable = AndroidSDK.emulatorExecutable() else {
            startProblem = "Android SDK not found."
            status = .noEmulator
            return
        }
        startProblem = nil
        self.profile = profile
        layout = DeviceFrameLayout(spec: Theme.Frame.spec, deviceSize: deviceSize)
        let process: Process
        do {
            process = try EmulatorLauncher.launch(executable: executable, avdName: avdName)
        } catch {
            log.error("Launch failed: \(String(describing: error), privacy: .public)")
            startProblem = "The emulator didn't start."
            status = .noEmulator
            return
        }
        log.info("Launched \(avdName, privacy: .public) as PID \(process.processIdentifier)")
        launchedProcess = process
        launchedAVDName = avdName
        status = .starting
        startTask?.cancel()
        startTask = Task { [weak self] in
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: Theme.Timing.startTimeout)
            while !Task.isCancelled, clock.now < deadline {
                guard let self, self.status == .starting else { return }
                self.startWatcher()
                self.refresh()
                if !process.isRunning, self.emulator == nil, self.status == .starting {
                    self.log.error("Emulator exited while starting, status \(process.terminationStatus)")
                    self.startProblem = "The emulator quit while starting."
                    self.status = .noEmulator
                    return
                }
                try? await Task.sleep(for: Theme.Timing.startPoll)
            }
            guard let self, self.status == .starting, !Task.isCancelled else { return }
            self.startProblem = "The emulator didn't start."
            self.status = .noEmulator
        }
    }

    /// Restarts the emulator on screen. Callers confirm first unless `ownsEmulator`.
    func restartEmulator() {
        guard let current = emulator else { return }
        let avdName = current.avdName
        let profile = profile
        log.info("Restarting \(avdName, privacy: .public), PID \(current.pid)")
        disconnect()
        if ownedEmulatorPID == current.pid { ownedEmulatorPID = nil }
        status = .starting
        launchedAVDName = avdName
        startTask?.cancel()
        startTask = Task { [weak self] in
            _ = await EmulatorLauncher.stop(
                pid: current.pid, gracePeriod: Theme.Timing.stopGracePeriod, killWait: Theme.Timing.stopKillWait,
                pollInterval: Theme.Timing.stopPoll)
            guard let self, !Task.isCancelled else { return }
            self.launch(avdName: avdName, profile: profile)
        }
    }

    // MARK: Connection

    private func connect(to emulator: RunningEmulator) {
        let wasStarting = status == .starting
        self.emulator = emulator
        if let launched = launchedProcess?.processIdentifier, launchedAVDName == emulator.avdName,
            emulator.pid == launched || EmulatorLauncher.parentPID(of: emulator.pid) == launched
        {
            ownedEmulatorPID = emulator.pid
        }
        if wasStarting { startTask?.cancel() }
        profile = emulator.avdDirectory.map(DeviceProfile.load(avdDirectory:)) ?? DeviceProfile()
        layout = DeviceFrameLayout(spec: Theme.Frame.spec, deviceSize: deviceSize)
        status = wasStarting ? .booting : .connecting
        hasFrame = false
        isBooted = false
        log.info(
            "Connecting to \(emulator.avdName, privacy: .public) on port \(emulator.grpcPort), version \(emulator.emulatorVersion ?? "?", privacy: .public), PID \(emulator.pid), owned \(self.ownsEmulator)"
        )

        let connection: EmulatorConnection
        do {
            connection = try EmulatorConnection(emulator: emulator, deviceSize: deviceSize)
        } catch {
            connectionFailed(error, on: nil)
            return
        }
        self.connection = connection
        connectionTask = Task {
            do {
                try await connection.run()
            } catch {
                self.connectionFailed(error, on: connection)
            }
        }
        watchBoot(on: connection)
        startFrames(on: connection)
    }

    /// Polls `getStatus` until Android has booted, then shows the screen.
    private func watchBoot(on connection: EmulatorConnection) {
        bootTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let booted = try await connection.status(timeout: Theme.Timing.statusTimeout).booted
                    guard let self, self.connection === connection else { return }
                    if booted {
                        self.isBooted = true
                        self.updateLiveStatus()
                        return
                    }
                    if self.status == .connecting { self.status = .booting }
                } catch is CancellationError {
                    return
                } catch {
                    self?.connectionFailed(error, on: connection)
                    return
                }
                try? await Task.sleep(for: Theme.Timing.bootPoll)
            }
        }
    }

    private func updateLiveStatus() {
        guard isBooted, hasFrame, status == .connecting || status == .booting else { return }
        status = .live
    }

    private func connectionFailed(_ error: any Error, on failed: EmulatorConnection?) {
        guard failed == nil || connection === failed else { return }
        log.error("Connection failed: \(String(describing: error), privacy: .public)")
        // A gone emulator is "no emulator", not an error.
        if let emulator, !EmulatorDiscovery.processIsAlive(emulator.pid) {
            refresh()
            return
        }
        let current = emulator
        disconnect()
        emulator = current
        status = .failed
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
                        guard let self, self.connection === connection else { return }
                        screenView.show(image)
                        self.hasFrame = true
                        self.updateLiveStatus()
                    }
                }
            } catch is CancellationError {
            } catch {
                await MainActor.run { self?.connectionFailed(error, on: connection) }
            }
        }
    }

    private func disconnect() {
        releaseAll()
        framesTask?.cancel()
        connectionTask?.cancel()
        bootTask?.cancel()
        connection?.shutdown()
        framesTask = nil
        connectionTask = nil
        bootTask = nil
        connection = nil
        emulator = nil
        hasFrame = false
        isBooted = false
        screenView.show(nil)
    }

    // MARK: Input

    private var mapping: ScreenMapping {
        ScreenMapping(
            screenRect: CGRect(origin: .zero, size: layout.screenRect.size), deviceSize: deviceSize)
    }

    private func handlePointer(_ phase: ScreenView.PointerPhase, at point: CGPoint) {
        log.debug("Pointer \(String(describing: phase), privacy: .public) at \(point.x), \(point.y)")
        guard let connection, status == .live else { return }
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
