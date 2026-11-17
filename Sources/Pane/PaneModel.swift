import AppKit
import Carbon.HIToolbox
import Observation
import PaneCore
import SwiftUI
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
    /// When the running recording started, or nil when not recording. Set inside an animation
    /// (`RecordButton.animation`), so the toolbar's other buttons glide to their new places.
    private(set) var recordingStartedAt: Date?
    /// False while the window is hidden, minimised or covered: the recording time stops ticking.
    var windowIsVisible = true
    /// A screenshot is on its way from the emulator: another press is ignored and Screenshot
    /// stays pressed until it lands.
    var captureGate = CaptureGate()
    /// Bumped when a screenshot lands, for the flash over the screen (`CaptureFlash`).
    var captureFlashes = 0
    /// The AVDs on disk, for Start and "Choose another emulator".
    private(set) var avds: [AvdInfo] = []
    /// Why the last Start didn't work, shown under the Start button.
    private(set) var startProblem: String?

    /// A start that hasn't answered after `Theme.Timing.slowStart`: the line says so and
    /// offers Stop.
    private(set) var isSlowStart = false

    /// A short line over the bottom of the screen ("Copied.", "Saved to Desktop.", an error),
    /// or nil.
    private(set) var notice: CaptureNotice?
    /// True while the notice's work is still running, for its spinner.
    private(set) var noticeIsBusy = false

    /// The device's theme and text size as last read, for the menus' ticks; nil when unknown.
    var deviceAppearance: DeviceAppearance?
    var deviceTextSize: DeviceTextSize?

    /// What Pane remembers between launches.
    @ObservationIgnored let settings: PaneSettings
    /// Inspect Layout, Measure and Pick Colour.
    @ObservationIgnored let tools = ToolsModel()
    /// Files dragged over and dropped on the device.
    @ObservationIgnored let drop = DropModel()

    /// Share Clipboard: text moves both ways while the window is key.
    var sharesClipboard: Bool {
        get { settings.sharesClipboard }
        set { settings.sharesClipboard = newValue }
    }

    /// The AVD Start launches. The last one chosen in any window is remembered for the next
    /// launch.
    var selectedAVDName: String? {
        didSet { if selectedAVDName != nil { settings.selectedAVDName = selectedAVDName } }
    }

    /// The AVD this window is about: the emulator on screen, the one starting, or the one
    /// Start would launch. One window per emulator is kept through this.
    var shownAVDName: String? { emulator?.avdName ?? launchedAVDName ?? selectedAVD?.name }

    /// Set by the app: whether another window already shows an AVD, and how to bring that
    /// window forward.
    /// Where the title's device name button is drawn (window content, y down), so the window
    /// can send a click there to the switcher, and whether the pointer is over it.
    @ObservationIgnored var switcherFrame = CGRect.zero
    private(set) var pointerOverTitle = false
    /// The keys are on the switcher's trigger: Esc closed the switcher and gave focus back to
    /// it, so Space, Return or Down opens it again. Any other key goes to the device (and
    /// takes focus with it), as does a click.
    var isTitleFocused = false
    /// The menu panel open over the window (More, the emulator switcher or the emulators
    /// menu); nil when none is.
    var menu: PaneMenu?
    /// Opens or closes More's menu (set by the window).
    @ObservationIgnored var onShowMore: () -> Void = {}
    /// Opens the emulators menu under a point in the window (set by the window).
    @ObservationIgnored var onShowEmulators: (CGPoint) -> Void = { _ in }
    /// The connection ended: the window closes any sheet that was about the device.
    @ObservationIgnored var onDeviceGone: () -> Void = {}
    /// Runs a menu command in this window (set by the window).
    @ObservationIgnored var onCommand: (DeviceCommand) -> Void = { _ in }
    /// Opens the emulator switcher under the title (set by the window).
    @ObservationIgnored var onShowSwitcher: () -> Void = {}
    @ObservationIgnored var isShownElsewhere: (String) -> Bool = { _ in false }
    /// The AVDs any Pane window is starting or waiting on to boot (set by the app).
    @ObservationIgnored var startingAVDs: () -> Set<String> = { [] }
    @ObservationIgnored var showWindow: (String) -> Void = { _ in }

    @ObservationIgnored let screenView = ScreenView(cornerRadius: Theme.Frame.screenRadius)
    @ObservationIgnored private(set) var connection: EmulatorConnection?
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
    /// The emulator this window launched (through the helper, or as Pane's child in a `swift run` build).
    @ObservationIgnored private var launchedEmulator: LaunchedEmulator?
    /// The launch waiting for its PID from the helper, so Stop pressed in that moment can still
    /// stop it once the PID arrives.
    @ObservationIgnored private var pendingLaunch: PendingLaunch?
    /// The emulators Pane started (any window), by the PID each registered with. Pane only
    /// ever stops these without asking.
    private static var ownedEmulatorPIDs: Set<Int32> = []
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
    /// The turns asked for and not yet shown by the emulator.
    @ObservationIgnored private var rotations = RotationRequests()
    /// The latest turn: its call, then the fresh frames that show it.
    @ObservationIgnored private var rotationTask: Task<Void, Never>?
    /// Counts the screen streams started, so a frame knows whether its stream is the latest.
    @ObservationIgnored private var streamGeneration = 0
    /// Frames the latest screen stream has delivered, in any orientation.
    @ObservationIgnored private var streamFrames = 0
    /// The recording the frame loop feeds, readable off the main actor.
    @ObservationIgnored nonisolated let recorderSlot = RecorderSlot()
    @ObservationIgnored let log = Logger(subsystem: "dev.niduslabs.pane", category: "model")
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored var exportTask: Task<Void, Never>?

    @ObservationIgnored private var clipboardSync = ClipboardSync()
    @ObservationIgnored private var clipboardTask: Task<Void, Never>?
    @ObservationIgnored private var pasteboardPollTask: Task<Void, Never>?
    /// The Mac clipboard's change count last seen, so only later changes are sent.
    @ObservationIgnored private var pasteboardChangeCount = PaneModel.pasteboard.changeCount

    var title: String { titleRow.title }

    var meta: String { titleRow.meta }

    /// The Start screen names the emulator Start would launch, so a second window isn't "Pane".
    private var titleRow: TitleRow {
        let state: TitleRow.State =
            switch status {
            case .noEmulator: .noEmulator
            case .starting: .starting
            case .connecting, .booting, .live: .connected
            case .failed: .failed
            }
        return TitleRow(
            state: state, emulatorName: emulator?.avdName, startingName: launchedAVDName, selected: selectedAVD,
            profile: profile)
    }

    /// The chosen AVD, else the first one no other window shows.
    var selectedAVD: AvdInfo? {
        avds.first { $0.name == selectedAVDName } ?? avds.first { !isShownElsewhere($0.name) } ?? avds.first
    }

    /// True when the emulator on screen is one Pane started, so it may restart it unasked.
    var ownsEmulator: Bool {
        guard let emulator else { return false }
        return Self.ownedEmulatorPIDs.contains(emulator.pid)
    }

    var deviceSize: PixelSize { profile.screenSize ?? Theme.Frame.fallbackDeviceSize }

    /// `initialAVD` is what a second window opens on; the first window passes nil and shows the
    /// AVD remembered from last time.
    init(settings: PaneSettings = .shared, initialAVD: String? = nil) {
        self.settings = settings
        selectedAVDName = initialAVD ?? settings.selectedAVDName
        tools.host = self
        screenView.onPointer = { [weak self] phase, point in self?.handlePointer(phase, at: point) }
        screenView.onScroll = { [weak self] point, dx, dy, phase in
            self?.handleScroll(at: point, deltaX: dx, deltaY: dy, phase: phase)
        }
        screenView.onKey = { [weak self] event, isDown in self?.handleKey(event, isDown: isDown) ?? false }
        screenView.onPaste = { [weak self] in self?.paste() }
        drop.onProblem = { [weak self] text in self?.showProblem(text) }
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
        if isShownElsewhere(avd.name) {
            showWindow(avd.name)
            return
        }
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
            Self.ownedEmulatorPIDs.remove(current.pid)
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
        // An emulator another window shows is that window's.
        let free = running.filter { !isShownElsewhere($0.avdName) }
        if let next = free.first(where: { $0.avdName == wanted }) ?? (status == .starting ? nil : free.first) {
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
        launchedEmulator = nil
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
        launchedAVDName = avdName
        status = .starting
        isSlowStart = false
        let withoutSound = settings.startsWithoutSound
        let ticket = PendingLaunch()
        pendingLaunch = ticket
        let helper = EmulatorLauncher.helperURL().map {
            EmulatorLauncher.Helper(url: $0, timings: Theme.Timing.helperLaunch)
        }
        if helper == nil { log.info("No Pane Emulator helper in the bundle; starting the emulator as Pane's child") }
        startTask?.cancel()
        startTask = Task { [weak self] in
            let launched: LaunchedEmulator
            do {
                launched = try await EmulatorLauncher.launch(
                    executable: executable, avdName: avdName, withoutSound: withoutSound,
                    outputLog: EmulatorLauncher.outputLog(avdName: avdName), helper: helper)
            } catch {
                guard let self else { return }
                if self.pendingLaunch === ticket { self.pendingLaunch = nil }
                guard !Task.isCancelled else { return }
                self.log.error("Launch failed: \(String(describing: error), privacy: .public)")
                self.startProblem = "The emulator didn't start."
                self.forgetLaunch()
                self.status = .noEmulator
                return
            }
            guard let self else { return }
            if self.pendingLaunch === ticket { self.pendingLaunch = nil }
            if ticket.stopPressed {
                self.log.info(
                    "Stopping \(avdName, privacy: .public), PID \(launched.pid): Stop was pressed while it launched")
                _ = await EmulatorLauncher.stop(
                    pid: launched.pid, gracePeriod: Theme.Timing.stopGracePeriod, killWait: Theme.Timing.stopKillWait,
                    pollInterval: Theme.Timing.stopPoll)
                return
            }
            // Anything else that moved on (a switch to another AVD) leaves it running, as a
            // closed window does.
            guard !Task.isCancelled, self.status == .starting, self.launchedAVDName == avdName else { return }
            self.log.info("Launched \(avdName, privacy: .public) as PID \(launched.pid)")
            self.launchedEmulator = launched
            self.waitForStart(of: avdName, launched: launched)
        }
    }

    /// Shows `avdName` starting and attaches once it registers. `launched` is the launch when
    /// Pane started it; nil for one started elsewhere (the emulator wrapper's attach request).
    private func waitForStart(of avdName: String, launched: LaunchedEmulator?) {
        launchedAVDName = avdName
        status = .starting
        isSlowStart = false
        startTask?.cancel()
        startTask = Task { [weak self] in
            let clock = ContinuousClock()
            let began = clock.now
            let deadline = began.advanced(by: Theme.Timing.startTimeout)
            while !Task.isCancelled, clock.now < deadline {
                guard let self, self.status == .starting else { return }
                if clock.now - began >= Self.slowStartDelay { self.isSlowStart = true }
                self.startWatcher()
                self.refresh()
                if let launched, !launched.isAlive, self.emulator == nil, self.status == .starting {
                    let status = launched.exitStatus.map { "status \($0)" } ?? "status unknown"
                    self.log.error("Emulator exited while starting, \(status, privacy: .public); its log says why")
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

    /// How long a start may take before the line changes. Debug builds take
    /// `-PaneSlowStartAfter <seconds>` so a check needn't wait.
    private static var slowStartDelay: Duration {
        #if DEBUG
            let seconds = UserDefaults.standard.double(forKey: "PaneSlowStartAfter")
            if seconds > 0 { return .seconds(seconds) }
        #endif
        return Theme.Timing.slowStart
    }

    /// Stop on a slow start: gives up waiting and shows Start again. An emulator Pane launched
    /// is stopped (by PID); one started elsewhere is left alone.
    func stopStarting() {
        guard status == .starting else { return }
        log.info("Stop pressed while starting")
        let launched = launchedEmulator
        pendingLaunch?.stopPressed = true
        pendingLaunch = nil
        forgetLaunch()
        isSlowStart = false
        status = .noEmulator
        guard let launched, launched.isAlive else { return }
        let pid = launched.pid
        Task {
            _ = await EmulatorLauncher.stop(
                pid: pid, gracePeriod: Theme.Timing.stopGracePeriod, killWait: Theme.Timing.stopKillWait,
                pollInterval: Theme.Timing.stopPoll)
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
            launchedEmulator = nil
            waitForStart(of: avdName, launched: nil)
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
        Self.ownedEmulatorPIDs.remove(current.pid)
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

    /// Shuts the emulator on screen down and shows Start. Callers confirm first unless
    /// `ownsEmulator`.
    func shutDownEmulator() {
        guard let current = emulator else { return }
        log.info("Shutting down \(current.avdName, privacy: .public), PID \(current.pid)")
        reconnectAttempt = 0
        reconnectTask?.cancel()
        selectedAVDName = current.avdName
        disconnect()
        Self.ownedEmulatorPIDs.remove(current.pid)
        forgetLaunch()
        status = .noEmulator
        Task {
            _ = await EmulatorLauncher.stop(
                pid: current.pid, gracePeriod: Theme.Timing.stopGracePeriod, killWait: Theme.Timing.stopKillWait,
                pollInterval: Theme.Timing.stopPoll)
        }
    }

    /// The emulator switcher's "Show in this window": attaches to a running AVD at once; one
    /// that isn't running goes to the Start screen, because Pane never starts an emulator on
    /// its own. The emulator this window showed keeps running. An AVD another window shows
    /// brings that window forward instead.
    func switchTo(avdName: String) {
        guard avdName != emulator?.avdName, !(status == .starting && launchedAVDName == avdName) else { return }
        if isShownElsewhere(avdName) {
            showWindow(avdName)
            return
        }
        log.info("Switching to \(avdName, privacy: .public)")
        reloadAVDs()
        reconnectTask?.cancel()
        reconnectAttempt = 0
        if emulator != nil { disconnect() }
        forgetLaunch()
        status = .noEmulator
        startProblem = nil
        selectedAVDName = avdName
        if let avd = selectedAVD { setProfile(avd.profile) }
        if let running = EmulatorDiscovery.runningEmulators(in: Self.registrationFolder).first(where: {
            $0.avdName == avdName
        }) {
            connect(to: running)
        }
    }

    /// The window is closing: lets go of the emulator (which keeps running) and stops watching.
    func close() {
        menu = nil
        tools.deactivate()
        exportTask?.cancel()
        reconnectTask?.cancel()
        startTask?.cancel()
        disconnect()
        watcher = nil
    }

    // MARK: Notices

    // MARK: Menu panels

    func closeMenu() { menu = nil }

    /// A row was chosen: the menu closes and the window runs its command.
    func choose(_ command: DeviceCommand) {
        menu = nil
        onCommand(command)
    }

    /// Shows a short line over the bottom of the screen. With `busy` it stays (with a spinner)
    /// until the next notice; otherwise it clears itself after `hold`.
    func showNotice(_ text: String, busy: Bool = false, for hold: Duration = Theme.Notice.doneDuration) {
        showNotice(CaptureNotice(text), busy: busy, for: hold)
    }

    /// Shows a notice whose folder name may be truncated in the middle (`CaptureNotice`).
    func showNotice(_ line: CaptureNotice, busy: Bool = false, for hold: Duration = Theme.Notice.doneDuration) {
        noticeTask?.cancel()
        notice = line
        noticeIsBusy = busy
        guard !busy else { return }
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: hold)
            guard let self, !Task.isCancelled else { return }
            self.notice = nil
        }
    }

    /// An error stays up longer so it can be read.
    func showProblem(_ text: String) {
        showProblem(CaptureNotice(text))
    }

    func showProblem(_ line: CaptureNotice) {
        NSSound.beep()
        showNotice(line, for: Theme.Notice.errorDuration)
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

    /// The smallest screen height for this device and orientation: the theme's floor, raised
    /// until the window is wide enough for the widest panel drawn inside it (the switcher).
    var minScreenHeight: CGFloat {
        DeviceFrameLayout.smallestScreenHeight(
            forWindowWidth: Theme.Window.minWidth, spec: Theme.Frame.spec, deviceSize: deviceSize,
            quadrants: quadrants, floor: Theme.Frame.minScreenHeight)
    }

    /// Rebuilds the layout; the window follows unless the user is resizing it. A turn to
    /// portrait can leave the screen under the minimum, so it grows back to it.
    private func relayout(resizeWindow: Bool) {
        if screenHeight < minScreenHeight { screenHeight = minScreenHeight }
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
            range: minScreenHeight...Theme.Frame.maxScreenHeight)
        return DeviceFrameLayout.screenHeight(
            fitting: contentSize, spec: spec, deviceSize: deviceSize, quadrants: quadrants,
            range: minScreenHeight...max(minScreenHeight, largest))
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
        ).map { max(minScreenHeight, $0.rounded()) }
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
        applySize(sizeAVDName.flatMap(settings.sizeMode(for:)) ?? .fit)
    }

    private func setSizeMode(_ mode: ScreenSizeMode?) {
        log.info(
            "Size \(mode?.rawValue ?? "manual", privacy: .public), long side \(self.screenHeight, privacy: .public)")
        sizeMode = mode
        guard let name = sizeAVDName else { return }
        settings.setSizeMode(mode, for: name)
    }

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

    /// Starts or stops a recording. The state changes inside `animation`, which the Record
    /// button passes (`Spring.toggle`; none under Reduce Motion), so the capsule's width
    /// and its neighbours move with it.
    func toggleRecording(animation: Animation? = nil) {
        if recordingStartedAt != nil {
            stopRecording(animation: animation)
        } else {
            startRecording(animation: animation)
        }
    }

    /// Records the frames already arriving into a movie in the screenshot folder, starting with
    /// the frame on screen now, so a screen that never changes still makes a movie. A movie is
    /// always a file, whatever macOS's recording target says (`CaptureOutcome`).
    ///
    /// The button shows recording at once; the writer is set up off the main actor
    /// (`FrameRecorder.start()`), since that can take 150 ms. If it can't start, the button
    /// goes back and Pane beeps, as when it failed before the button changed. A Stop that comes
    /// first ends it instead, through Stop's own "couldn't save" path.
    private func startRecording(animation: Animation?) {
        guard status == .live, let size = streamRequest?.size else { return }
        let now = Date()
        let url = CaptureFileName.unusedURL(
            in: Self.captureFolder, prefix: "Pane Recording", date: now, fileExtension: "mov")
        let recorder = FrameRecorder(
            url: url, size: size, start: FrameStats.microseconds(at: now), firstFrame: screenView.latestFrame)
        recorderSlot.current = recorder
        withAnimation(animation) { recordingStartedAt = now }
        log.info("Recording to \(url.lastPathComponent, privacy: .public)")
        let log = log
        Task { [weak self] in
            do {
                try await recorder.start()
            } catch {
                log.error("Recording failed to start: \(String(describing: error), privacy: .public)")
                self?.recordingFailedToStart(recorder, animation: animation)
            }
        }
    }

    /// Takes the button back out of recording after `recorder` couldn't start, unless Stop
    /// already ended it.
    private func recordingFailedToStart(_ recorder: FrameRecorder, animation: Animation?) {
        guard recorderSlot.current === recorder else { return }
        recorderSlot.current = nil
        withAnimation(animation) { recordingStartedAt = nil }
        NSSound.beep()
    }

    /// Ends the recording, if any, and returns once the movie is written. The frame on screen
    /// is written again at Stop, so the movie is as long as the recording. The pill then says
    /// where it went, or that it couldn't be saved.
    @discardableResult
    func stopRecording(animation: Animation? = nil) -> Task<Void, Never>? {
        guard let recorder = recorderSlot.current else { return nil }
        recorderSlot.current = nil
        let stop = FrameStats.nowMicroseconds()
        let onScreen = screenView.latestFrame
        withAnimation(animation) { recordingStartedAt = nil }
        let log = log
        let settings = settings
        let folder = recorder.url.deletingLastPathComponent()
        return Task { [weak self] in
            do {
                try await recorder.finish(at: stop, onScreen: onScreen, wait: Theme.Timing.recordingEncoderWait)
                settings.lastRecording = recorder.url
                log.info("Saved recording \(recorder.url.lastPathComponent, privacy: .public)")
                self?.showNotice(.recordingSaved(to: folder))
            } catch {
                log.error("Recording not saved: \(String(describing: error), privacy: .public)")
                self?.showProblem(.recordingFailed)
            }
        }
    }

    // MARK: Screenshot

    /// Settings' Save to: by default where macOS saves screenshots (`CaptureLocation`), read at
    /// each capture so a change in the Screenshot app applies at once. Debug builds take `-PaneCaptureFolder <path>` (checks
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
        return CaptureLocation.folder(for: PaneSettings.shared.captureDestination, configured: configured)
    }

    /// macOS's Save to (`target` keys), read at each capture. Debug builds take
    /// `-PaneScreenCaptureTarget <value>`, which stands in for every target key so checks never
    /// read or change the real setting.
    static var captureTargets: SystemCaptureTargets {
        #if DEBUG
            if let target = UserDefaults.standard.string(forKey: "PaneScreenCaptureTarget") {
                return SystemCaptureTargets(target: target)
            }
        #endif
        return SystemCaptureTargets.current()
    }

    // MARK: Rotation

    /// Turns the device a quarter counter-clockwise (Device Hub's "Rotate Left"). The layout
    /// follows when the first frame in the new orientation arrives.
    ///
    /// The emulator sends a frame only when Android redraws, and a screen that doesn't turn
    /// (the launcher, a portrait-only app, upside down on a phone) doesn't, so that frame
    /// could take seconds or never come. Once the call returns, the stream restarts every
    /// time its first frame (always sent) still shows the old orientation, until a frame
    /// shows the turn or `rotationRefreshLimit` passes. A stream whose first frame takes
    /// longer than `rotationRefresh` is restarted anyway. Presses count from the last turn asked for, so each
    /// turns once more; their calls go out in order, and a newer press takes over the wait.
    func rotate() {
        guard let connection, status == .live else { return }
        let target = rotations.ask(from: quadrants)
        releaseAll()
        let previous = rotationTask
        previous?.cancel()
        rotationTask = Task { [weak self] in
            await previous?.value
            do {
                try await connection.rotate(toQuadrants: target)
            } catch {
                self?.log.error("Rotate failed: \(String(describing: error), privacy: .public)")
                self?.rotations.giveUp(on: target)
                return
            }
            let deadline = ContinuousClock.now + Theme.Timing.rotationRefreshLimit
            while let self, !Task.isCancelled, self.rotations.isWaiting(for: target), self.connection === connection,
                ContinuousClock.now < deadline
            {
                self.restartFrames(on: connection)
                let restartedAt = ContinuousClock.now
                while !Task.isCancelled, self.streamFrames == 0, self.rotations.isWaiting(for: target),
                    ContinuousClock.now - restartedAt < Theme.Timing.rotationRefresh
                {
                    try? await Task.sleep(for: Theme.Timing.rotationPoll)
                }
            }
            guard let self, !Task.isCancelled, self.rotations.isWaiting(for: target) else { return }
            self.log.info("Turn to \(target) not shown; following any orientation again")
            self.rotations.giveUp(on: target)
        }
    }

    /// Asks for frames again with the same request: a new stream's first frame comes at
    /// once, whether or not the screen changed.
    private func restartFrames(on connection: EmulatorConnection) {
        restartFramesTask?.cancel()
        framesTask?.cancel()
        startFrames(on: connection)
    }

    /// A frame arrived in another orientation than the stream was asked for: turn the layout
    /// (keeping the screen's size, within the display) and ask for frames in the new shape.
    private func orientationChanged(to newQuadrants: Int, on connection: EmulatorConnection) {
        rotations.shown(newQuadrants)
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
        restartFrames(on: connection)
    }

    // MARK: Connection

    private func connect(to emulator: RunningEmulator) {
        let wasStarting = status == .starting
        self.emulator = emulator
        if let launched = launchedEmulator?.pid, launchedAVDName == emulator.avdName,
            emulator.pid == launched || EmulatorLauncher.parentPID(of: emulator.pid) == launched
        {
            Self.ownedEmulatorPIDs.insert(emulator.pid)
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
        deviceBecameLive()
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
        streamGeneration += 1
        streamFrames = 0
        let generation = streamGeneration
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
                    // The recording is read on the main actor as the frame is shown, so every
                    // frame after the one Start wrote first is recorded, and none twice.
                    let recorder: FrameRecorder? = await MainActor.run {
                        guard let self, self.connection === connection else { return nil }
                        if generation == self.streamGeneration { self.streamFrames += 1 }
                        // Frames in an orientation the stream wasn't asked for are dropped, and
                        // the stream restarts in the new one (as Android Studio does).
                        if frame.rotationQuadrants != self.streamRequest?.quadrants {
                            // While a turn is under way the emulator eases the angle and can
                            // pass through another orientation (180 to -90 goes via 0); only
                            // the ones asked for count.
                            guard self.rotations.follows(frame.rotationQuadrants) else { return nil }
                            self.orientationChanged(to: frame.rotationQuadrants, on: connection)
                            return nil
                        }
                        screenView.show(frame)
                        self.hasFrame = true
                        self.updateLiveStatus()
                        self.tools.screenChanged()
                        return self.recorderSlot.current
                    }
                    if let recorder {
                        await recorder.append(frame)
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

    func disconnect() {
        releaseAll()
        stopRecording()
        tools.deactivate()
        menu = nil
        onDeviceGone()
        deviceAppearance = nil
        deviceTextSize = nil
        clipboardTask?.cancel()
        clipboardTask = nil
        drop.reset()
        framesTask?.cancel()
        connectionTask?.cancel()
        bootTask?.cancel()
        restartFramesTask?.cancel()
        streamRequest = nil
        rotationTask?.cancel()
        rotationTask = nil
        rotations.reset()
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
        // While a tool is on, the screen's clicks are the tool's and never reach the device.
        if tools.isActive {
            tools.pointer(phase, at: point)
            return
        }
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
        guard let connection, status == .live, pressedAt == nil, !tools.isActive else { return }
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
        if let menu {
            // An open menu takes the keys: arrows, Return, Esc and letters. None reach the device.
            let command = event.modifierFlags.contains(.command)
            guard isDown else { return !command }
            let result = menu.handleKey(
                code: Int(event.keyCode), characters: event.charactersIgnoringModifiers, command: command)
            switch result {
            case .close:
                closeMenu()
                if menu.anchor == .title { isTitleFocused = true }
            case .choose(let command): choose(command)
            case .handled: break
            case .ignored: if command { return false }
            }
            return true
        }
        if isTitleFocused, isDown, event.modifierFlags.intersection([.command, .option, .control]).isEmpty {
            switch Int(event.keyCode) {
            case kVK_Space, kVK_Return, kVK_ANSI_KeypadEnter, kVK_DownArrow:
                onShowSwitcher()
                return true
            case kVK_Escape:
                isTitleFocused = false
                return true
            default:
                isTitleFocused = false
            }
        }
        if tools.isActive {
            // Esc leaves the tool; every other key is kept from the device.
            if isDown, Int(event.keyCode) == kVK_Escape { tools.deactivate() }
            return !event.modifierFlags.contains(.command)
        }
        // The drop card's Return (open the app just installed) and Esc (dismiss).
        if isDown, event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
            drop.handleKey(code: Int(event.keyCode))
        {
            return true
        }
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

    /// What the drop needs to know about this window's emulator.
    private var dropContext: DropModel.Context {
        let live = status == .live ? emulator : nil
        return DropModel.Context(
            emulatorName: live?.avdName, adb: live.flatMap(Adb.init(emulator:)), showsRefusal: status == .noEmulator)
    }

    /// Files are being dragged over the window (nil: they left). True when a drop would be
    /// taken; the drag card shows either way.
    func dragChanged(files: [URL]?) -> Bool {
        drop.dragChanged(files: files, context: dropContext)
    }

    /// Files dropped on the window: installs the apps and copies the rest (`DropModel`).
    func drop(files: [URL]) -> Bool {
        drop.drop(files: files, context: dropContext)
    }

    // MARK: Clipboard

    var isKey: Bool {
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

    #if DEBUG
        /// `pane://check-switcher-hover?title=1`: posted pointer moves don't reach a background
        /// window's tracking, so checks set the title's hover here.
        func checkPointerOverTitle(_ over: Bool) { pointerOverTitle = over }
    #endif

    /// The pointer moved over the window (window coordinates, y down), or left it (nil).
    func pointerMoved(to point: CGPoint?) {
        let overTitle = point.map(switcherFrame.contains) ?? false
        if overTitle != pointerOverTitle { pointerOverTitle = overTitle }
        if tools.isActive {
            if nearButton != nil { nearButton = nil }
            tools.hover(at: point.map { CGPoint(x: $0.x - layout.screenRect.minX, y: $0.y - layout.screenRect.minY) })
            return
        }
        let near = point.flatMap { layout.nearestButton(to: $0, within: Theme.Frame.buttonProximity) }
        if near != nearButton { nearButton = near }
    }

    /// The Mac clipboard was just written by Pane itself (a copied colour or screenshot): not
    /// a change to send to the device.
    func noteOwnPasteboardWrite() {
        pasteboardChangeCount = Self.pasteboard.changeCount
    }

    /// Presses or releases a frame button. Power is held for as long as the mouse is down, so a
    /// long press opens Android's power menu.
    func setButton(_ button: FrameButton, isDown: Bool) {
        guard let connection else { return }
        if isDown {
            guard !tools.isActive else { return }
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

/// One Start's launch while it waits for the helper's PID.
@MainActor private final class PendingLaunch {
    var stopPressed = false
}
