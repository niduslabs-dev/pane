import AppKit
import Carbon.HIToolbox
import Observation
import PaneCore
import Synchronization
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
    /// The frame button the pointer is near, which slides out.
    private(set) var nearButton: FrameButton?
    /// Frame buttons held down right now, so focus loss can release them.
    private(set) var heldButtons: Set<FrameButton> = []
    /// Quarter turns counter-clockwise from portrait, from the latest frame.
    private(set) var quadrants = 0
    /// The screen's long side in points; the window's size follows from it.
    private(set) var screenHeight = Theme.Frame.screenHeight
    /// Where the title starts: just past the system's traffic lights, measured by the window.
    var titleLeadingInset = Theme.Window.fallbackTitleLeading
    /// The Window menu size in effect (ticked), or nil after a manual resize.
    private(set) var sizeMode: ScreenSizeMode?
    /// When the running recording started, or nil when not recording.
    private(set) var recordingStartedAt: Date?
    /// The AVDs on disk, for Start and "Choose another emulator".
    private(set) var avds: [AvdInfo] = []
    /// Why the last Start didn't work, shown under the Start button.
    private(set) var startProblem: String?

    /// The label while files are dragged over the window ("Install app"), or nil.
    private(set) var dropHover: String?
    /// The drop's status line ("Installing Splito…", "Installed.", or adb's error), or nil.
    private(set) var transferStatus: String?
    /// True while adb runs, for the spinner.
    private(set) var isTransferring = false

    /// Share Clipboard (More menu): text moves both ways while the window is key. On unless
    /// turned off, remembered.
    var sharesClipboard: Bool = UserDefaults.standard.object(forKey: PaneModel.shareClipboardKey) as? Bool ?? true {
        didSet { UserDefaults.standard.set(sharesClipboard, forKey: Self.shareClipboardKey) }
    }

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
    @ObservationIgnored private var scroll = ScrollGesture()
    @ObservationIgnored private var wheelReleaseTask: Task<Void, Never>?
    /// Named keys held down right now (arrows, Backspace), so focus loss can release them.
    @ObservationIgnored private var heldKeys: Set<String> = []
    /// The emulator process Pane launched, and the PID of the emulator it became once it
    /// registered. Pane only ever stops these without asking.
    @ObservationIgnored private var launchedProcess: Process?
    @ObservationIgnored private var ownedEmulatorPID: Int32?
    /// Failed tries since the connection last worked; drives the backoff.
    private(set) var reconnectAttempt = 0
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?
    @ObservationIgnored private var hasFrame = false
    @ObservationIgnored private var isBooted = false
    /// The window resizes itself to this when the layout changes for any reason but a drag.
    @ObservationIgnored var onWindowContentSizeChange: ((CGSize) -> Void)?
    /// What the running screen stream was asked for, so a resize only restarts it on change.
    @ObservationIgnored private var streamRequest: StreamRequest?
    @ObservationIgnored private var restartFramesTask: Task<Void, Never>?
    /// The orientation last asked for and not yet shown by the emulator.
    @ObservationIgnored private var pendingQuadrants: Int?
    /// The recording the frame loop feeds, readable off the main actor.
    @ObservationIgnored nonisolated let recorderSlot = RecorderSlot()
    @ObservationIgnored private let log = Logger(subsystem: "dev.niduslabs.pane", category: "model")

    private static let selectedAVDKey = "selectedAVD"
    private static let shareClipboardKey = "shareClipboard"
    @ObservationIgnored private var transferTask: Task<Void, Never>?
    @ObservationIgnored private var clipboardSync = ClipboardSync()
    @ObservationIgnored private var clipboardTask: Task<Void, Never>?
    @ObservationIgnored private var pasteboardPollTask: Task<Void, Never>?
    /// The Mac clipboard's change count last seen, so only later changes are sent.
    @ObservationIgnored private var pasteboardChangeCount = PaneModel.pasteboard.changeCount

    var title: String {
        switch status {
        case .noEmulator: "Pane"
        case .starting: launchedAVDName ?? selectedAVD?.name ?? "Pane"
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
        screenView.onScroll = { [weak self] point, dx, dy, phase in
            self?.handleScroll(at: point, deltaX: dx, deltaY: dy, phase: phase)
        }
        screenView.onKey = { [weak self] event, isDown in self?.handleKey(event, isDown: isDown) ?? false }
    }

    /// Starts watching for emulators and attaches to the first one running.
    func start() {
        log.info(
            "Screenshots and recordings save to \(Self.captureFolder.path(percentEncoded: false), privacy: .public)")
        reloadAVDs()
        startWatcher()
        refresh()
        applyRememberedSize()
        #if DEBUG
            if UserDefaults.standard.bool(forKey: "PaneTreatAsKey") { windowBecameKey() }
        #endif
    }

    func reloadAVDs() {
        avds = AvdCatalog.list(in: Self.avdHome)
        runningAVDNames = Set(EmulatorDiscovery.runningEmulators(in: Self.registrationFolder).map(\.avdName))
        if status == .noEmulator, let avd = selectedAVD { setProfile(avd.profile) }
    }

    /// AVDs with an emulator running right now, for the menu's Running tags.
    private(set) var runningAVDNames: Set<String> = []

    /// `~/.android/avd`. Debug builds take `-PaneAVDHome <path>`, so checks can show a fixture
    /// list without creating real AVDs.
    static var avdHome: URL {
        #if DEBUG
            if let path = UserDefaults.standard.string(forKey: "PaneAVDHome") {
                return URL(filePath: path, directoryHint: .isDirectory)
            }
        #endif
        return AvdCatalog.directory()
    }

    /// The emulators' registration folder. Debug builds take `-PaneRegistrationFolder <path>`,
    /// so checks can fake an emulator starting and stopping without touching real ones.
    static var registrationFolder: URL {
        #if DEBUG
            if let path = UserDefaults.standard.string(forKey: "PaneRegistrationFolder") {
                return URL(filePath: path, directoryHint: .isDirectory)
            }
        #endif
        return EmulatorDiscovery.registrationDirectory()
    }

    /// Chosen in the menu: attaches when that AVD is running, otherwise shows it with Start ready.
    func choose(_ avd: AvdInfo) {
        selectAVD(avd.name)
        guard runningAVDNames.contains(avd.name),
            let running = EmulatorDiscovery.runningEmulators(in: Self.registrationFolder).first(where: {
                $0.avdName == avd.name
            })
        else { return }
        if emulator != nil { disconnect() }
        connect(to: running)
    }

    func selectAVD(_ name: String) {
        selectedAVDName = name
        startProblem = nil
        if status == .noEmulator, let avd = selectedAVD { setProfile(avd.profile) }
    }

    private func startWatcher() {
        guard watcher == nil else { return }
        let watcher = RegistrationWatcher(directory: Self.registrationFolder) { [weak self] in
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
        let running = EmulatorDiscovery.runningEmulators(in: Self.registrationFolder)
        if let current = emulator, !running.contains(where: { $0.pid == current.pid }) {
            // Stopped from outside (`adb emu kill`, a crash): show Start, never relaunch it. The
            // launch that started it is forgotten, so nothing can pick it up again.
            log.info("Emulator \(current.avdName, privacy: .public) is gone; showing Start")
            disconnect()
            if ownedEmulatorPID == current.pid { ownedEmulatorPID = nil }
            if status != .starting {
                forgetLaunch()
                status = .noEmulator
            }
        }
        guard emulator == nil else { return }
        #if DEBUG
            // `-PaneNoAutoAttach YES` keeps the no-emulator screen up while one runs, so checks
            // can show the menu's Running tag and attach from it.
            if status == .noEmulator, UserDefaults.standard.bool(forKey: "PaneNoAutoAttach") { return }
        #endif
        let wanted = status == .starting ? launchedAVDName : selectedAVDName
        if let next = running.first(where: { $0.avdName == wanted }) ?? (status == .starting ? nil : running.first) {
            connect(to: next)
        }
    }

    // MARK: Starting and restarting

    /// The AVD being started (by Pane, or elsewhere for an attach request), for the title.
    private(set) var launchedAVDName: String?

    /// Drops what Pane knows about the emulator it launched (once it is gone).
    private func forgetLaunch() {
        startTask?.cancel()
        startTask = nil
        launchedProcess = nil
        launchedAVDName = nil
    }

    /// Launches the selected AVD headless and shows its progress until it is live. Only the
    /// Start button calls this: Pane never starts an emulator on its own.
    func startSelectedEmulator() {
        log.info("Start pressed")
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
        setProfile(profile)
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
        waitForStart(of: avdName, process: process)
    }

    /// Shows `avdName` starting and attaches once it registers. `process` is the launch when
    /// Pane started it; nil for one started elsewhere (the emulator wrapper's attach request).
    private func waitForStart(of avdName: String, process: Process?) {
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
                if let process, !process.isRunning, self.emulator == nil, self.status == .starting {
                    self.log.error("Emulator exited while starting, status \(process.terminationStatus)")
                    self.startProblem = "The emulator quit while starting."
                    self.forgetLaunch()
                    self.status = .noEmulator
                    return
                }
                try? await Task.sleep(for: Theme.Timing.startPoll)
            }
            guard let self, self.status == .starting, !Task.isCancelled else { return }
            self.startProblem = "The emulator didn't start."
            self.forgetLaunch()
            self.status = .noEmulator
        }
    }

    /// Shows an AVD that something else is starting or has started (the emulator wrapper:
    /// `pane://attach?avd=` or `--attach`). Attaches if it is running, else waits for it. Never
    /// launches anything, and never stops the emulator on screen.
    func requestAttach(avdName: String) {
        log.info("Attach requested for \(avdName, privacy: .public)")
        reloadAVDs()
        selectedAVDName = avdName
        startProblem = nil
        let running = EmulatorDiscovery.runningEmulators(in: Self.registrationFolder).first { $0.avdName == avdName }
        if let running, emulator?.pid == running.pid { return }
        if status == .starting, launchedAVDName == avdName { return }
        reconnectTask?.cancel()
        reconnectAttempt = 0
        if emulator != nil { disconnect() }
        if let avd = avds.first(where: { $0.name == avdName }) { setProfile(avd.profile) }
        if let running {
            status = .noEmulator
            connect(to: running)
        } else {
            launchedProcess = nil
            waitForStart(of: avdName, process: nil)
        }
    }

    /// Restarts the emulator on screen. Callers confirm first unless `ownsEmulator`.
    func restartEmulator() {
        guard let current = emulator else { return }
        log.info("Restart chosen")
        reconnectAttempt = 0
        reconnectTask?.cancel()
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

    // MARK: Size and layout

    private struct StreamRequest: Equatable {
        var size: PixelSize
        var quadrants: Int
    }

    private func setProfile(_ profile: DeviceProfile) {
        let oldSize = deviceSize
        let oldDensity = self.profile.density
        self.profile = profile
        if deviceSize != oldSize || profile.density != oldDensity {
            relayout(resizeWindow: true)
            if screenView.window != nil { applyRememberedSize() }
        }
    }

    /// Rebuilds the layout; the window follows unless the user is resizing it.
    private func relayout(resizeWindow: Bool) {
        let next = DeviceFrameLayout(
            spec: Theme.Frame.spec, deviceSize: deviceSize, screenHeight: screenHeight, quadrants: quadrants)
        guard next != layout else { return }
        layout = next
        if resizeWindow { onWindowContentSizeChange?(next.windowContentSize) }
        scheduleFrameRestart()
    }

    /// The screen height whose layout fits a proposed window content size, kept between the
    /// theme's minimum and what fits in `available` (the screen's visible area).
    func screenHeight(fitting contentSize: CGSize, available: CGSize) -> CGFloat {
        let spec = Theme.Frame.spec
        let largest = DeviceFrameLayout.screenHeight(
            fitting: available, spec: spec, deviceSize: deviceSize, quadrants: quadrants,
            range: Theme.Frame.minScreenHeight...Theme.Frame.maxScreenHeight)
        return DeviceFrameLayout.screenHeight(
            fitting: contentSize, spec: spec, deviceSize: deviceSize, quadrants: quadrants,
            range: Theme.Frame.minScreenHeight...max(Theme.Frame.minScreenHeight, largest))
    }

    /// The window content size for a screen height, at the current device and orientation.
    func windowContentSize(screenHeight: CGFloat) -> CGSize {
        DeviceFrameLayout(
            spec: Theme.Frame.spec, deviceSize: deviceSize, screenHeight: screenHeight, quadrants: quadrants
        ).windowContentSize
    }

    /// The user resized the window to a size `windowWillResize` already snapped to the shape.
    /// A manual size clears the Window menu's tick.
    func windowResized(screenHeight: CGFloat) {
        guard screenHeight != self.screenHeight else { return }
        self.screenHeight = screenHeight
        setSizeMode(nil)
        relayout(resizeWindow: false)
    }

    // MARK: Window menu sizes

    private var sizeAVDName: String? { emulator?.avdName ?? selectedAVD?.name }

    /// The display the window is on, for Physical Size and Pixel Accurate.
    private var displayMetrics: DisplayMetrics? {
        guard let screen = screenView.window?.screen ?? NSScreen.main else { return nil }
        let millimetres: CGFloat
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            millimetres = CGDisplayScreenSize(CGDirectDisplayID(number.uint32Value)).width
        } else {
            millimetres = 0
        }
        return DisplayMetrics(
            backingScale: screen.backingScaleFactor, widthPoints: screen.frame.width, widthMillimetres: millimetres)
    }

    /// The screen's long side for a size, or nil when this display can't show it.
    private func longSide(for mode: ScreenSizeMode) -> CGFloat? {
        if mode == .fit {
            guard let available = screenView.window?.screen?.visibleFrame.size ?? NSScreen.main?.visibleFrame.size
            else { return nil }
            return screenHeight(fitting: available, available: available)
        }
        guard let display = displayMetrics else { return nil }
        return ScreenSizing.longSide(
            mode, deviceSize: deviceSize, density: profile.density ?? Theme.Frame.fallbackDensity, display: display
        ).map { max(Theme.Frame.minScreenHeight, $0.rounded()) }
    }

    func isAvailable(_ mode: ScreenSizeMode) -> Bool { longSide(for: mode) != nil }

    /// Sizes the window for a Window menu size and remembers it for this AVD. Physical and
    /// Pixel sizes may be taller than the screen; the window then hangs off the bottom.
    func applySize(_ mode: ScreenSizeMode) {
        guard let side = longSide(for: mode) else { return }
        setSizeMode(mode)
        guard side != screenHeight else { return }
        screenHeight = side
        relayout(resizeWindow: true)
    }

    /// Re-applies the size after the window moved to another display or its scale changed.
    func displayChanged() {
        guard let mode = sizeMode else { return }
        applySize(mode)
    }

    /// The remembered size for the AVD on screen, Fit Screen the first time.
    func applyRememberedSize() {
        let stored = sizeAVDName.flatMap { UserDefaults.standard.string(forKey: Self.sizeKeyPrefix + $0) }
        applySize(stored.flatMap(ScreenSizeMode.init(rawValue:)) ?? .fit)
    }

    private func setSizeMode(_ mode: ScreenSizeMode?) {
        log.info(
            "Size \(mode?.rawValue ?? "manual", privacy: .public), long side \(self.screenHeight, privacy: .public)")
        sizeMode = mode
        guard let name = sizeAVDName else { return }
        UserDefaults.standard.set(mode?.rawValue, forKey: Self.sizeKeyPrefix + name)
    }

    private static let sizeKeyPrefix = "sizeMode."

    private var zoomSizes: [CGFloat] { ScreenSizeMode.allCases.compactMap(longSide(for:)) }

    func canZoom(in up: Bool) -> Bool {
        ScreenSizing.step(from: screenHeight, among: zoomSizes, up: up) != nil
    }

    /// Steps to the next Window menu size up or down from the current one.
    func zoom(in up: Bool) {
        guard let next = ScreenSizing.step(from: screenHeight, among: zoomSizes, up: up) else { return }
        let tolerance: CGFloat = 1
        if let mode = ScreenSizeMode.allCases.first(where: {
            longSide(for: $0).map { abs($0 - next) <= tolerance } ?? false
        }) {
            applySize(mode)
        }
    }

    /// The window moved to a display with another backing scale: ask for sharper or smaller frames.
    func backingScaleChanged() { scheduleFrameRestart() }

    /// Restarts the screen stream at the new size once resizing settles, and only when the size
    /// or orientation to ask for actually changed.
    private func scheduleFrameRestart() {
        guard connection != nil else { return }
        restartFramesTask?.cancel()
        restartFramesTask = Task { [weak self] in
            try? await Task.sleep(for: Theme.Timing.frameRestartDebounce)
            guard let self, !Task.isCancelled, let connection = self.connection else { return }
            guard self.currentStreamRequest() != self.streamRequest else { return }
            self.framesTask?.cancel()
            self.startFrames(on: connection)
        }
    }

    private func currentStreamRequest() -> StreamRequest {
        let backingScale = screenView.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        let size = ScreenMapping.requestedImageSize(
            screenPoints: layout.screenRect.size, backingScale: backingScale, deviceSize: deviceSize,
            quadrants: quadrants)
        return StreamRequest(size: size, quadrants: quadrants)
    }

    // MARK: Home

    /// Android's Home key (`GoHome`, as Android Studio sends it), pressed and released.
    func pressHome() {
        guard let connection, status == .live else { return }
        connection.send(.key(name: Self.homeKeyName, isDown: true))
        connection.send(.key(name: Self.homeKeyName, isDown: false))
    }

    private static let homeKeyName = "GoHome"

    // MARK: Recording

    func toggleRecording() {
        if recordingStartedAt != nil {
            stopRecording()
        } else {
            startRecording()
        }
    }

    /// Records the frames already arriving into a movie in the screenshot folder.
    private func startRecording() {
        guard status == .live, let size = streamRequest?.size else { return }
        let url = CaptureFileName.unusedURL(
            in: Self.captureFolder, prefix: "Pane Recording", date: Date(), fileExtension: "mov")
        do {
            recorderSlot.current = try FrameRecorder(url: url, size: size)
            recordingStartedAt = Date()
            log.info("Recording to \(url.lastPathComponent, privacy: .public)")
        } catch {
            log.error("Recording failed to start: \(String(describing: error), privacy: .public)")
            NSSound.beep()
        }
    }

    /// Ends the recording, if any, and returns once the movie is written.
    @discardableResult
    func stopRecording() -> Task<Void, Never>? {
        guard let recorder = recorderSlot.current else { return nil }
        recorderSlot.current = nil
        recordingStartedAt = nil
        let log = log
        return Task {
            do {
                try await recorder.finish()
                log.info("Saved recording \(recorder.url.lastPathComponent, privacy: .public)")
            } catch {
                log.error("Recording not saved: \(String(describing: error), privacy: .public)")
            }
        }
    }

    // MARK: Screenshot

    /// Saves a full-size PNG of the screen to the screenshot folder, named as macOS names its own.
    func saveScreenshot() {
        guard let connection, status == .live else { return }
        let folder = Self.captureFolder
        Task { [weak self] in
            do {
                let png = try await connection.screenshotPNG()
                let url = CaptureFileName.unusedURL(in: folder, prefix: "Pane", date: Date(), fileExtension: "png")
                try png.write(to: url, options: .withoutOverwriting)
                self?.log.info("Saved screenshot \(url.lastPathComponent, privacy: .public)")
            } catch {
                self?.log.error("Screenshot failed: \(String(describing: error), privacy: .public)")
                NSSound.beep()
            }
        }
    }

    /// Where macOS saves screenshots (`CaptureLocation`), read at each capture so a change in
    /// the Screenshot app applies at once. Debug builds take `-PaneCaptureFolder <path>` (checks
    /// never write to the real folder) and `-PaneScreenCaptureLocation <value>`, which stands in
    /// for the system setting so checks never change it.
    static var captureFolder: URL {
        #if DEBUG
            if let path = UserDefaults.standard.string(forKey: "PaneCaptureFolder") {
                return URL(filePath: path, directoryHint: .isDirectory)
            }
            let configured =
                UserDefaults.standard.string(forKey: "PaneScreenCaptureLocation")
                ?? CaptureLocation.configuredLocation()
        #else
            let configured = CaptureLocation.configuredLocation()
        #endif
        return CaptureLocation.folder(configured: configured)
    }

    // MARK: Rotation

    /// Turns the device a quarter counter-clockwise (Device Hub's "Rotate Left"). The layout
    /// follows when the first frame in the new orientation arrives.
    func rotate() {
        guard let connection, status == .live else { return }
        let quarterTurnsInACircle = 4
        // The emulator can take seconds to show a turn; presses meanwhile count from the last
        // one asked for, so each press turns once more.
        let target = ((pendingQuadrants ?? quadrants) + 1) % quarterTurnsInACircle
        pendingQuadrants = target
        releaseAll()
        Task { [weak self] in
            do {
                try await connection.rotate(toQuadrants: target)
                try? await Task.sleep(for: Theme.Timing.rotationSettle)
            } catch {
                self?.log.error("Rotate failed: \(String(describing: error), privacy: .public)")
            }
            // Never shown (or failed): stop waiting for it, so any orientation is followed again.
            if let self, self.pendingQuadrants == target { self.pendingQuadrants = nil }
        }
    }

    /// A frame arrived in another orientation than the stream was asked for: turn the layout
    /// (keeping the screen's size, within the display) and ask for frames in the new shape.
    private func orientationChanged(to newQuadrants: Int, on connection: EmulatorConnection) {
        if newQuadrants == pendingQuadrants { pendingQuadrants = nil }
        guard newQuadrants != quadrants else { return }
        log.info(
            "Orientation \(self.quadrants) -> \(newQuadrants), size \(self.sizeMode?.rawValue ?? "manual", privacy: .public)"
        )
        releaseAll()
        quadrants = newQuadrants
        if sizeMode == .fit, let side = longSide(for: .fit) {
            screenHeight = side
        } else if sizeMode == nil, let available = screenView.window?.screen?.visibleFrame.size {
            screenHeight = min(screenHeight, screenHeight(fitting: available, available: available))
        }
        relayout(resizeWindow: true)
        restartFramesTask?.cancel()
        framesTask?.cancel()
        startFrames(on: connection)
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
        setProfile(emulator.avdDirectory.map(DeviceProfile.load(avdDirectory:)) ?? DeviceProfile())
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
        startClipboard(on: connection)
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
                    } else if self.status == .connecting {
                        self.status = .booting
                    }
                } catch is CancellationError {
                    return
                } catch {
                    guard !Task.isCancelled else { return }
                    self?.connectionFailed(error, on: connection)
                    return
                }
                // Once booted, the same call is the heartbeat.
                let booted = self?.isBooted ?? false
                try? await Task.sleep(for: booted ? Theme.Timing.heartbeat : Theme.Timing.bootPoll)
            }
        }
    }

    private func updateLiveStatus() {
        guard isBooted, hasFrame, status == .connecting || status == .booting else { return }
        status = .live
        reconnectAttempt = 0
    }

    private func connectionFailed(_ error: any Error, on failed: EmulatorConnection?) {
        guard failed == nil || connection === failed else { return }
        log.error("Connection failed: \(String(describing: error), privacy: .public)")
        // A gone emulator is "no emulator", not an error.
        if let emulator, !EmulatorDiscovery.processIsAlive(emulator.pid) {
            refresh()
            return
        }
        guard let current = emulator else { return }
        disconnect()
        reconnectAttempt += 1
        guard let delay = Theme.Timing.reconnect.delay(beforeAttempt: reconnectAttempt) else {
            log.error("Giving up on \(current.avdName, privacy: .public) after \(self.reconnectAttempt - 1) retries")
            emulator = current
            status = .failed
            return
        }
        log.info("Reconnecting, try \(self.reconnectAttempt), in \(delay, privacy: .public)")
        emulator = current
        status = .connecting
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled, self.status == .connecting, self.connection == nil else { return }
            // Re-read the registration: a restarted emulator has a new port and token.
            let running = EmulatorDiscovery.runningEmulators(in: Self.registrationFolder)
            guard let fresh = running.first(where: { $0.pid == current.pid }) else {
                self.emulator = nil
                self.status = .noEmulator
                self.reconnectAttempt = 0
                self.refresh()
                return
            }
            self.emulator = nil
            self.connect(to: fresh)
        }
    }

    private func startFrames(on connection: EmulatorConnection) {
        let request = currentStreamRequest()
        streamRequest = request
        let size = request.size
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
                    if let recorder = self?.recorderSlot.current, let image {
                        await recorder.append(image, timestampMicroseconds: frame.timestampMicroseconds)
                    }
                    await MainActor.run {
                        guard let self, self.connection === connection else { return }
                        // Frames in an orientation the stream wasn't asked for are dropped, and
                        // the stream restarts in the new one (as Android Studio does).
                        if frame.rotationQuadrants != self.streamRequest?.quadrants {
                            // While a turn is under way the emulator eases the angle and can
                            // pass through another orientation (180 to -90 goes via 0); only
                            // the one asked for counts.
                            if let pending = self.pendingQuadrants, frame.rotationQuadrants != pending { return }
                            self.orientationChanged(to: frame.rotationQuadrants, on: connection)
                            return
                        }
                        screenView.show(image)
                        self.hasFrame = true
                        self.updateLiveStatus()
                    }
                }
            } catch is CancellationError {
            } catch {
                // A stream cancelled for a restart ends with an error too; only others count.
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.connectionFailed(error, on: connection) }
            }
        }
    }

    private func disconnect() {
        releaseAll()
        stopRecording()
        clipboardTask?.cancel()
        clipboardTask = nil
        transferTask?.cancel()
        transferTask = nil
        dropHover = nil
        transferStatus = nil
        isTransferring = false
        framesTask?.cancel()
        connectionTask?.cancel()
        bootTask?.cancel()
        restartFramesTask?.cancel()
        streamRequest = nil
        pendingQuadrants = nil
        connection?.shutdown()
        framesTask = nil
        connectionTask = nil
        bootTask = nil
        connection = nil
        emulator = nil
        hasFrame = false
        isBooted = false
        scroll = ScrollGesture()
        screenView.show(nil)
    }

    // MARK: Input

    private var mapping: ScreenMapping {
        ScreenMapping(
            screenRect: CGRect(origin: .zero, size: layout.screenRect.size), deviceSize: deviceSize,
            quadrants: quadrants)
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

    /// Scrolls by dragging a finger on the device's screen (see `ScrollGesture`).
    private func handleScroll(at point: CGPoint, deltaX: CGFloat, deltaY: CGFloat, phase: ScrollGesture.Phase?) {
        guard let connection, status == .live, pressedAt == nil else { return }
        let gesturePhase: ScrollGesture.Phase
        var delta = CGVector(dx: deltaX, dy: deltaY)
        if let phase {
            gesturePhase = phase
        } else {
            gesturePhase = .wheel
            delta = CGVector(dx: deltaX * Theme.Timing.wheelLinePoints, dy: deltaY * Theme.Timing.wheelLinePoints)
        }
        let bounds = CGRect(origin: .zero, size: layout.screenRect.size)
        for action in scroll.handle(phase: gesturePhase, pointer: point, delta: delta, bounds: bounds) {
            send(action, on: connection)
        }
        guard gesturePhase == .wheel else { return }
        wheelReleaseTask?.cancel()
        wheelReleaseTask = Task { [weak self] in
            try? await Task.sleep(for: Theme.Timing.wheelRelease)
            guard let self, !Task.isCancelled, let action = self.scroll.endWheel(), let connection = self.connection
            else { return }
            self.send(action, on: connection)
        }
    }

    private func send(_ action: ScrollGesture.Action, on connection: EmulatorConnection) {
        switch action {
        case .down(let point), .move(let point): connection.send(.press(mapping.clampedDevicePoint(for: point)))
        case .up(let point): connection.send(.release(mapping.clampedDevicePoint(for: point)))
        }
    }

    /// Sends a key while the window is key. Command shortcuts stay with the Mac's menus.
    func handleKey(_ event: NSEvent, isDown: Bool) -> Bool {
        guard let connection, status == .live else { return false }
        if event.modifierFlags.contains(.command) {
            let shortcut = event.modifierFlags.intersection([.command, .shift, .option, .control])
            guard shortcut == .command, Int(event.keyCode) == kVK_ANSI_V else { return false }
            if isDown { paste() }
            return true
        }
        if let name = KeyMapping.keyName(macKeyCode: event.keyCode) {
            if isDown {
                heldKeys.insert(name)
            } else {
                guard heldKeys.remove(name) != nil else { return true }
            }
            connection.send(.key(name: name, isDown: isDown))
            return true
        }
        guard isDown else { return true }
        if event.modifierFlags.contains(.control) { return false }
        guard let text = event.characters.flatMap(KeyMapping.typedText) else { return false }
        connection.send(.text(text))
        return true
    }

    // MARK: Drag and drop

    /// Files are being dragged over the window: shows what a drop would do. False when nothing
    /// in the drag can be dropped now.
    func dragChanged(files: [URL]?) -> Bool {
        guard let files, status == .live, !isTransferring else {
            dropHover = nil
            return false
        }
        let plan = DropPlan(files: files)
        dropHover = plan.isEmpty ? nil : plan.hoverLabel
        return !plan.isEmpty
    }

    /// Files dropped on the window: installs the apps and copies the rest with adb, one at a
    /// time, showing each on the status line.
    func drop(files: [URL]) -> Bool {
        dropHover = nil
        guard status == .live, !isTransferring, let emulator else { return false }
        let plan = DropPlan(files: files)
        guard !plan.isEmpty else { return false }
        guard let adb = Adb(emulator: emulator) else {
            finishTransfer("adb not found.", after: Theme.Drop.errorDuration)
            return false
        }
        log.info("Drop: \(plan.steps.count) file(s)")
        isTransferring = true
        transferTask = Task { [weak self] in
            var result = plan.doneText
            var hold = Theme.Drop.doneDuration
            for step in plan.steps {
                guard let self, !Task.isCancelled else { return }
                self.transferStatus = DropPlan.progressText(for: step)
                do {
                    try await adb.run(step)
                } catch let failure as Adb.Failure {
                    self.log.error("Drop failed: \(failure.message, privacy: .public)")
                    (result, hold) = (failure.message, Theme.Drop.errorDuration)
                    break
                } catch {
                    self.log.error("Drop failed: \(String(describing: error), privacy: .public)")
                    (result, hold) = ("adb didn't run.", Theme.Drop.errorDuration)
                    break
                }
            }
            guard let self, !Task.isCancelled else { return }
            self.isTransferring = false
            self.finishTransfer(result, after: hold)
        }
        return true
    }

    /// Shows the result, then clears the status line.
    private func finishTransfer(_ text: String, after hold: Duration) {
        transferStatus = text
        transferTask = Task { [weak self] in
            try? await Task.sleep(for: hold)
            guard let self, !Task.isCancelled, !self.isTransferring else { return }
            self.transferStatus = nil
            self.transferTask = nil
        }
    }

    // MARK: Clipboard

    private var isKey: Bool {
        #if DEBUG
            if UserDefaults.standard.bool(forKey: "PaneTreatAsKey") { return true }
        #endif
        return NSApp.isActive && screenView.window?.isKeyWindow == true
    }

    /// The Mac's clipboard. Debug builds take `-PanePasteboard <name>` (a private pasteboard)
    /// and `-PaneTreatAsKey YES`, so background checks never touch the real clipboard or need
    /// the window in front.
    static var pasteboard: NSPasteboard {
        #if DEBUG
            if let name = UserDefaults.standard.string(forKey: "PanePasteboard") {
                return NSPasteboard(name: NSPasteboard.Name(name))
            }
        #endif
        return .general
    }

    /// Follows the device's clipboard for as long as the connection lasts. Contents are never
    /// logged.
    private func startClipboard(on connection: EmulatorConnection) {
        clipboardSync.reset()
        clipboardTask?.cancel()
        clipboardTask = Task { [weak self] in
            do {
                // An unreadable clipboard counts as empty: the first copy on the device is new.
                let baseline = (try? await connection.clipboardText()) ?? ""
                guard let self, self.connection === connection else { return }
                self.clipboardSync.deviceBaseline(baseline)
                for try await text in connection.clipboardUpdates() {
                    guard self.connection === connection else { return }
                    self.log.debug("Clipboard: device update")
                    let action = self.clipboardSync.deviceChanged(
                        to: text, isKey: self.isKey, isEnabled: self.sharesClipboard)
                    if case .setMac(let text) = action {
                        Self.pasteboard.clearContents()
                        Self.pasteboard.setString(text, forType: .string)
                        self.pasteboardChangeCount = Self.pasteboard.changeCount
                        self.log.info("Clipboard: device to Mac")
                    }
                }
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                self?.log.error("Clipboard stream ended: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// The window became key: from now on a change to the Mac's clipboard goes to the device.
    /// What is on it already stays put until pasted.
    func windowBecameKey() {
        pasteboardChangeCount = Self.pasteboard.changeCount
        pasteboardPollTask?.cancel()
        pasteboardPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Theme.Timing.clipboardPoll)
                guard let self, !Task.isCancelled else { return }
                let count = Self.pasteboard.changeCount
                guard count != self.pasteboardChangeCount else { continue }
                self.pasteboardChangeCount = count
                guard let connection = self.connection, self.status == .live else { continue }
                let action = self.clipboardSync.macChanged(
                    to: Self.pasteboard.string(forType: .string), isKey: self.isKey,
                    isEnabled: self.sharesClipboard)
                if case .setDevice(let text) = action {
                    self.log.info("Clipboard: Mac to device")
                    try? await connection.setClipboard(text)
                }
            }
        }
    }

    func windowResignedKey() {
        pasteboardPollTask?.cancel()
        pasteboardPollTask = nil
    }

    /// Command-V in the window: the Mac's text goes to the device (when sharing is on), then
    /// Android's paste shortcut is pressed.
    func paste() {
        guard let connection, status == .live else { return }
        let action = clipboardSync.pasteRequested(
            macText: Self.pasteboard.string(forType: .string), isEnabled: sharesClipboard)
        Task { [weak self] in
            if case .setDevice(let text) = action {
                self?.log.info("Clipboard: Mac to device for paste")
                do {
                    try await connection.setClipboard(text)
                    try? await Task.sleep(for: Theme.Timing.pasteAfterClipboard)
                } catch {
                    self?.log.error("Clipboard not set: \(String(describing: error), privacy: .public)")
                }
            }
            for (name, isDown) in Self.pasteKeys { connection.send(.key(name: name, isDown: isDown)) }
        }
    }

    /// Control-V, Android's paste shortcut on a hardware keyboard.
    private static let pasteKeys: [(String, Bool)] = [("Control", true), ("v", true), ("v", false), ("Control", false)]

    private func releasePointer() {
        guard let point = pressedAt else { return }
        connection?.send(.release(point))
        pressedAt = nil
    }

    /// The pointer moved over the window (window coordinates, y down), or left it (nil).
    func pointerMoved(to point: CGPoint?) {
        let near = point.flatMap { layout.nearestButton(to: $0, within: Theme.Frame.buttonProximity) }
        if near != nearButton { nearButton = near }
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
        wheelReleaseTask?.cancel()
        if let action = scroll.endWheel(), let connection { send(action, on: connection) }
        for name in heldKeys { connection?.send(.key(name: name, isDown: false)) }
        heldKeys.removeAll()
        for button in heldButtons { setButton(button, isDown: false) }
    }
}

/// The running recording, shared between the main actor (start and stop) and the frame loop.
final class RecorderSlot: Sendable {
    private let lock = Mutex<FrameRecorder?>(nil)

    var current: FrameRecorder? {
        get { lock.withLock { $0 } }
        set { lock.withLock { $0 = newValue } }
    }
}
