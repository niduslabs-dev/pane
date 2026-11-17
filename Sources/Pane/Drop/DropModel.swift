import AppKit
import Carbon.HIToolbox
import Observation
import PaneCore
import os

/// Files dropped on the device (the canvas's option A with the refined drag card, variant 1).
/// While files hover the window it shows the drag card: the first frame from the file alone,
/// then what `aapt2 dump badging` and the device say. After the drop it runs the files in
/// order (apps first) and shows each one's result; a finished card closes itself, a question or
/// a failure stays until dismissed.
@MainActor
@Observable
final class DropModel {
    /// What the window knows when a drag arrives.
    struct Context {
        /// The live emulator's AVD name; nil when there is none.
        var emulatorName: String?
        var adb: Adb?
        /// Show the refused card ("Start an emulator first") rather than nothing: only on the
        /// no-emulator screen.
        var showsRefusal: Bool
    }

    struct Drag: Equatable {
        var items: [DraggedItem]
        var card: DragCard
        /// The emulator the card names; nil on the no-emulator screen.
        var emulator: String?
        var isReading = false
        /// Reading has taken longer than `Theme.Drop.spinnerDelay`.
        var showsSpinner = false
    }

    private(set) var drag: Drag?
    private(set) var job: DropJob?
    /// The AVD the running or finished drop went to, for "Installed on dev_android36".
    private(set) var jobEmulator = ""
    /// Icons read out of `.apk`s, by file.
    private(set) var icons: [URL: NSImage] = [:]
    /// Details is open: adb's own line shows under the failure.
    private(set) var showsDetails = false
    /// Esc while the drop runs hides the card; a question or a failure brings it back.
    private(set) var isHidden = false
    /// The pointer is over the card, which holds a finished card open.
    var isHovered = false {
        didSet { if oldValue != isHovered { scheduleDismissal() } }
    }

    /// Something to say outside the card (Open didn't work), set by the window.
    @ObservationIgnored var onProblem: (String) -> Void = { _ in }

    @ObservationIgnored private let log = Logger(subsystem: "dev.niduslabs.pane", category: "drop")
    @ObservationIgnored private var readTask: Task<Void, Never>?
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var dismissTask: Task<Void, Never>?
    @ObservationIgnored private var adb: Adb?
    @ObservationIgnored private var finishedAt: ContinuousClock.Instant?
    @ObservationIgnored private var confirmedDowngrades: Set<Int> = []
    /// aapt's answer per file version (path, size and modification date); nil when it failed.
    @ObservationIgnored private var badgingCache: [String: ApkBadging?] = [:]
    /// The device's copy of each package; nil when not installed. Cleared for another emulator.
    @ObservationIgnored private var installedCache: [String: InstalledPackage?] = [:]
    @ObservationIgnored private var cacheSerial: String?
    @ObservationIgnored private lazy var aapt2 = AndroidSDK.aapt2Executable()

    /// The card is on the screen.
    var showsCard: Bool { drag != nil || (job != nil && !isHidden) }
    /// The screen dims under the card and the moss outline shows: a drop that will be taken, or
    /// one running or finished.
    var dimsScreen: Bool { (drag.map { !$0.card.isRefused } ?? false) || (drag == nil && job != nil && !isHidden) }
    var isRunning: Bool { job.map { !$0.isFinished } ?? false }

    // MARK: Dragging

    /// Files entered the window (or left it: nil). True when a drop would be taken.
    func dragChanged(files: [URL]?, context: Context) -> Bool {
        guard let files else {
            endDrag()
            return false
        }
        if let drag, drag.items.map(\.url) == files, drag.card.source == (context.emulatorName ?? "Pane") {
            return !drag.card.isRefused
        }
        endDrag()
        // A drop that is still running keeps its card; the new files wait for it.
        guard !isRunning else { return false }
        resetCaches(for: context.adb)
        let items = files.map { url in
            var item = DraggedItem(url: url, isDirectory: DropPlan.isDirectory(url), size: DropPlan.size(of: url))
            fillFromCache(&item)
            return item
        }
        guard let card = DragCard(items: items, emulator: context.emulatorName) else { return false }
        // With no live emulator the refusal shows only on the no-emulator screen; a folder
        // dragged over a live one always says why it's refused.
        if context.emulatorName == nil && !context.showsRefusal { return false }
        // A finished card gives way to the new drag.
        if job != nil { dismissNow() }
        drag = Drag(items: items, card: card, emulator: context.emulatorName)
        if card.isRefused {
            announce(card.announcement)
            return false
        }
        startReading(context: context)
        return true
    }

    /// The drag left or ended without a drop.
    func endDrag() {
        readTask?.cancel()
        readTask = nil
        drag = nil
    }

    private func startReading(context: Context) {
        guard let drag else { return }
        let apps = drag.items.indices.filter { drag.items[$0].isApp && drag.items[$0].isUsable }
            .prefix(Theme.Drop.maxReadsWhileDragging)
        let needsReading = apps.contains { drag.items[$0].badging == nil || drag.items[$0].change == nil }
        // The card draws the icons of one app, or of the first two in a stack.
        let iconApps = Set(apps.prefix(Theme.Drop.stackCount - 1))
        guard needsReading || iconApps.contains(where: { icons[drag.items[$0].url] == nil }) else {
            announce(drag.card.announcement)
            return
        }
        self.drag?.isReading = true
        readTask = Task { [weak self] in
            let spinner = Task { [weak self] in
                try? await Task.sleep(for: Theme.Drop.spinnerDelay)
                guard !Task.isCancelled, let self, self.drag?.isReading == true else { return }
                self.drag?.showsSpinner = true
            }
            defer { spinner.cancel() }
            #if DEBUG
                // Checks hold the first frame (`-PaneDropReadDelay <seconds>`) to capture it.
                let hold = UserDefaults.standard.double(forKey: "PaneDropReadDelay")
                if hold > 0 { try? await Task.sleep(for: .seconds(hold)) }
            #endif
            for index in apps {
                guard let self, !Task.isCancelled, let url = self.drag?.items[index].url else { return }
                let badging = await self.readBadging(url)
                guard !Task.isCancelled, self.drag?.items[index].url == url else { return }
                self.updateDragItem(index) { $0.badging = badging }
                if let badging, let adb = context.adb {
                    let installed = await self.installed(badging.packageName, adb: adb)
                    guard !Task.isCancelled, self.drag?.items[index].url == url else { return }
                    self.updateDragItem(index) { $0.change = VersionChange(installing: badging, over: installed) }
                }
                if iconApps.contains(index), let badging, badging.hasDrawableIcon, let path = badging.iconPath {
                    await self.readIcon(url, path: path)
                }
            }
            guard let self, !Task.isCancelled, let drag = self.drag else { return }
            self.drag?.isReading = false
            self.drag?.showsSpinner = false
            self.announce(drag.card.announcement)
        }
    }

    private func updateDragItem(_ index: Int, _ change: (inout DraggedItem) -> Void) {
        guard var drag, drag.items.indices.contains(index) else { return }
        change(&drag.items[index])
        if let card = DragCard(items: drag.items, emulator: drag.emulator) {
            drag.card = card
        }
        self.drag = drag
    }

    // MARK: Dropping

    /// Files were dropped. Starts the drop and returns true when it was taken.
    func drop(files: [URL], context: Context) -> Bool {
        let read = drag.flatMap { $0.items.map(\.url) == files ? $0.items : nil }
        endDrag()
        guard let name = context.emulatorName, let adb = context.adb, !isRunning else { return false }
        resetCaches(for: adb)
        let items =
            read
            ?? files.map { url in
                var item = DraggedItem(url: url, isDirectory: DropPlan.isDirectory(url), size: DropPlan.size(of: url))
                fillFromCache(&item)
                return item
            }
        let job = DropJob(dragged: items)
        guard !job.isEmpty else { return false }
        log.info("Drop: \(job.items.count) file(s)")
        dismissTask?.cancel()
        self.adb = adb
        self.job = job
        jobEmulator = name
        finishedAt = nil
        confirmedDowngrades = []
        showsDetails = false
        isHidden = false
        runQueue()
        return true
    }

    private func runQueue() {
        guard let adb else { return }
        runTask = Task { [weak self] in
            while let self, !Task.isCancelled, let index = self.job?.nextWaiting {
                await self.run(index, adb: adb)
            }
            guard let self, !Task.isCancelled, let job = self.job else { return }
            if let asking = job.asking {
                self.isHidden = false
                self.announce(Self.downgradeQuestion(asking, emulator: self.jobEmulator))
            } else if job.isFinished {
                self.finish()
            }
        }
    }

    private func run(_ index: Int, adb: Adb) async {
        guard var item = job?.items[index] else { return }
        if item.isApp {
            if item.badging == nil {
                item.badging = await readBadging(item.file)
                setItem(index) { $0.badging = item.badging }
            }
            if let badging = item.badging, item.change == nil {
                let change = VersionChange(installing: badging, over: await installed(badging.packageName, adb: adb))
                item.change = change
                setItem(index) { $0.change = change }
            }
            let confirmed = confirmedDowngrades.contains(item.id)
            if item.change?.isDowngrade == true && !confirmed {
                setItem(index) { $0.state = .asking }
                return
            }
            if let badging = item.badging, badging.hasDrawableIcon, let path = badging.iconPath,
                icons[item.file] == nil
            {
                await readIcon(item.file, path: path)
            }
            await install(index, item: item, adb: adb, allowDowngrade: confirmed)
        } else {
            await copy(index, item: item, adb: adb)
        }
    }

    private func install(_ index: Int, item: DropJob.Item, adb: Adb, allowDowngrade: Bool) async {
        let staging = DropTransfer.stagingPath(token: String(UUID().uuidString.prefix(8)))
        guard await push(index, item: item, to: staging, adb: adb, isApp: true) else {
            _ = try? await adb.run(DropTransfer.removeArguments(devicePath: staging))
            return
        }
        setItem(index) { $0.state = .installing }
        let result = await Self.attempt {
            try await adb.run(
                DropTransfer.installArguments(devicePath: staging, allowDowngrade: allowDowngrade),
                timeout: Theme.Drop.transferTimeout)
        }
        _ = try? await adb.run(DropTransfer.removeArguments(devicePath: staging))
        switch result {
        case .success(let output) where DropTransfer.installSucceeded(status: output.status, output: output.text):
            if let badging = item.badging {
                installedCache[badging.packageName] = InstalledPackage(
                    versionCode: badging.versionCode, versionName: badging.versionName)
            }
            setItem(index) { $0.state = .installed }
            log.info("Drop: installed one app")
        case .success(let output):
            let failure = DropFailure.install(item.name, output: output.text)
            log.error("Drop: install failed: \(failure.code ?? "", privacy: .public)")
            setItem(index) { $0.state = .failed(failure) }
        case .failure(let error):
            setItem(index) { $0.state = .failed(.adbDidNotRun(item.name, isApp: true, reason: Self.text(of: error))) }
        }
    }

    private func copy(_ index: Int, item: DropJob.Item, adb: Adb) async {
        let path = DropPlan.devicePath(for: item.file)
        guard await push(index, item: item, to: path, adb: adb, isApp: false) else { return }
        if case .file(isMedia: true) = item.kind {
            // Best effort: the file is on the device either way.
            _ = try? await adb.run(DropTransfer.mediaScanArguments(devicePath: path))
        }
        setItem(index) { $0.state = .copied }
    }

    /// Sends one file, reading how much has arrived while it goes. False when it failed (the
    /// item then says why).
    private func push(_ index: Int, item: DropJob.Item, to devicePath: String, adb: Adb, isApp: Bool) async -> Bool {
        setItem(index) { $0.state = .sending(sent: 0, total: item.size) }
        let poll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Theme.Drop.progressPoll)
                guard !Task.isCancelled,
                    let output = try? await adb.run(DropTransfer.sizeArguments(devicePath: devicePath)),
                    let sent = DropTransfer.parseSize(output.text), !Task.isCancelled, let self
                else { continue }
                if case .sending = self.job?.items[index].state {
                    self.setItem(index) { $0.state = .sending(sent: sent, total: item.size) }
                }
            }
        }
        let result = await Self.attempt {
            try await adb.run(
                DropTransfer.pushArguments(item.file, to: devicePath), timeout: Theme.Drop.transferTimeout)
        }
        poll.cancel()
        switch result {
        case .success(let output) where output.status == 0:
            return true
        case .success(let output):
            setItem(index) { $0.state = .failed(.copy(item.name, output: output.text, isApp: isApp)) }
        case .failure(let error):
            setItem(index) { $0.state = .failed(.adbDidNotRun(item.name, isApp: isApp, reason: Self.text(of: error))) }
        }
        log.error("Drop: push failed")
        return false
    }

    private func setItem(_ index: Int, _ change: (inout DropJob.Item) -> Void) {
        guard var job, job.items.indices.contains(index) else { return }
        change(&job.items[index])
        self.job = job
    }

    private func finish() {
        guard let job else { return }
        finishedAt = .now
        log.info("Drop: finished, \(job.failures.count) failed")
        if !job.failures.isEmpty { isHidden = false }
        announce(Self.summary(job))
        scheduleDismissal()
    }

    // MARK: Answers and buttons

    /// The downgrade question's answer: Install older version (true) or Cancel. Cancel on a
    /// drop of one file closes the card.
    func answerDowngrade(install: Bool) {
        guard var job, let index = job.items.firstIndex(where: { $0.state == .asking }) else { return }
        if install {
            confirmedDowngrades.insert(job.items[index].id)
            job.items[index].state = .waiting
        } else {
            job.items[index].state = .skipped
        }
        self.job = job
        if !install && job.items.count == 1 {
            dismissNow()
            return
        }
        runQueue()
    }

    /// Open (an installed app) or Show (Downloads), then the card closes.
    func perform(_ item: DropJob.Item) {
        guard let intent = DeviceIntent.after(item), let adb else { return }
        dismissNow()
        Task { [weak self] in
            var arguments = intent.arguments
            if arguments == nil, case .openApp(let package, _) = intent {
                let resolved = try? await adb.run(DeviceIntent.resolveArguments(package: package))
                arguments = resolved.flatMap { DeviceIntent.parseResolved($0.text) }
                    .map(DeviceIntent.startArguments(component:))
            }
            guard let arguments else {
                self?.onProblem("This app has no screen to open.")
                return
            }
            let output = try? await adb.run(arguments)
            if !(output.map { DeviceIntent.started(status: $0.status, output: $0.text) } ?? false) {
                self?.onProblem(intent == .showDownloads ? "Couldn't open Downloads." : "Couldn't open the app.")
            }
        }
    }

    func toggleDetails() { showsDetails.toggle() }

    /// adb's lines for every failure, for Copy.
    var detailsText: String {
        guard let job else { return "" }
        let failures = job.failures
        if job.items.count == 1 { return failures.first?.failure?.code ?? "" }
        return failures.compactMap { item in item.failure?.code.map { "\(item.file.lastPathComponent): \($0)" } }
            .joined(separator: "\n")
    }

    /// Return and Esc while the card is up. Return opens the newest installed app (or answers
    /// Cancel to a question); Esc dismisses. True when the key was the card's.
    func handleKey(code: Int) -> Bool {
        guard drag == nil, let job, !isHidden else { return false }
        switch code {
        case kVK_Escape:
            if job.asking != nil { answerDowngrade(install: false) } else { dismiss() }
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if job.asking != nil {
                answerDowngrade(install: false)
                return true
            }
            guard job.isFinished, let last = job.lastInstalled, DeviceIntent.after(last) != nil else { return false }
            perform(last)
            return true
        default:
            return false
        }
    }

    /// Close (or Esc): a finished card goes; a running drop only hides its card.
    func dismiss() {
        if isRunning {
            isHidden = true
        } else {
            dismissNow()
        }
    }

    private func dismissNow() {
        dismissTask?.cancel()
        dismissTask = nil
        if isRunning { runTask?.cancel() }
        runTask = nil
        job = nil
        showsDetails = false
        isHidden = false
        isHovered = false
    }

    /// The emulator went away: everything stops and the caches are dropped.
    func reset() {
        endDrag()
        dismissNow()
        installedCache = [:]
        cacheSerial = nil
        adb = nil
    }

    private func scheduleDismissal() {
        dismissTask?.cancel()
        guard let job else { return }
        switch DropDismissal.decide(
            job: job, finishedAt: finishedAt, now: .now, isHovered: isHovered, afterDone: Theme.Drop.afterDone)
        {
        case .stay: return
        case .close:
            log.info("Drop: the finished card closed itself")
            dismissNow()
        case .wait(let delay):
            dismissTask = Task { [weak self] in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                self?.scheduleDismissal()
            }
        }
    }

    // MARK: Reading

    private func cacheKey(_ url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return
            "\(url.path)|\(values?.fileSize ?? -1)|\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)"
    }

    private func fillFromCache(_ item: inout DraggedItem) {
        guard item.isApp, let cached = badgingCache[cacheKey(item.url)] else { return }
        item.badging = cached
        if let badging = cached, let installed = installedCache[badging.packageName] {
            item.change = VersionChange(installing: badging, over: installed)
        }
    }

    private func resetCaches(for adb: Adb?) {
        guard let serial = adb?.serial, serial != cacheSerial else { return }
        installedCache = [:]
        cacheSerial = serial
    }

    private func readBadging(_ url: URL) async -> ApkBadging? {
        let key = cacheKey(url)
        if let cached = badgingCache[key] { return cached }
        guard let aapt2 else { return nil }
        let output = try? await Adb.runProcess(
            aapt2, ["dump", "badging", url.path(percentEncoded: false)], timeout: Theme.Drop.readTimeout)
        let badging = output.flatMap {
            $0.status == 0 ? ApkBadging.parse(String(decoding: $0.data, as: UTF8.self)) : nil
        }
        badgingCache[key] = .some(badging)
        return badging
    }

    private func installed(_ package: String, adb: Adb) async -> InstalledPackage? {
        if let cached = installedCache[package] { return cached }
        guard
            let output = try? await adb.run(
                InstalledPackage.lookupArguments(packageName: package), timeout: Theme.Drop.readTimeout)
        else { return nil }
        let installed = InstalledPackage.parse(output.text)
        installedCache[package] = .some(installed)
        return installed
    }

    private func readIcon(_ apk: URL, path: String) async {
        guard icons[apk] == nil,
            let output = try? await Adb.runProcess(
                URL(filePath: "/usr/bin/unzip"), ["-p", apk.path(percentEncoded: false), path],
                timeout: Theme.Drop.readTimeout),
            output.status == 0, let image = NSImage(data: output.data)
        else { return }
        icons[apk] = image
    }

    // MARK: Words

    private func announce(_ text: String) {
        NSAccessibility.post(
            element: NSApp as Any, notification: .announcementRequested,
            userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    static func downgradeQuestion(_ item: DropJob.Item, emulator: String) -> String {
        guard case .older(let installed) = item.change else { return "" }
        let version = item.badging.map { VersionChange.name($0.versionName, code: $0.versionCode) } ?? ""
        return "\(emulator) has \(installed). Going back to \(version) can break the app's saved data."
    }

    static func summary(_ job: DropJob) -> String {
        if job.items.count == 1, let item = job.items.first {
            switch item.state {
            case .installed: return "Installed \(item.name)."
            case .copied: return "Copied \(item.name) to Downloads."
            case .failed(let failure): return [failure.title, failure.body].compactMap { $0 }.joined(separator: " ")
            default: return job.title
            }
        }
        return job.title + "."
    }

    private static func attempt<T: Sendable>(_ work: () async throws -> T) async -> Result<T, any Error> {
        do { return .success(try await work()) } catch { return .failure(error) }
    }

    private static func text(of error: any Error) -> String {
        (error as? Adb.Failure)?.message ?? String(describing: error)
    }
}
