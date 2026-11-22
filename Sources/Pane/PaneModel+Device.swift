import AppKit
import PaneCore
import UniformTypeIdentifiers

/// The More menu's device actions: screenshots, GIF export, opening links, and the device's
/// appearance, text size and location.
extension PaneModel {
    // MARK: Screenshots

    /// The toolbar's Screenshot button: a file, the clipboard or Preview, as Save to and macOS's
    /// own Save to say (`CaptureOutcome`).
    func takeScreenshot() {
        let outcome = CaptureOutcome.resolve(
            .screenshotButton, destination: settings.captureDestination, targets: Self.captureTargets)
        switch outcome {
        case .file: saveScreenshot()
        case .clipboard: copyScreenshot()
        case .preview: previewScreenshot()
        }
    }

    /// Saves a full-size PNG of the screen to the screenshot folder, named as macOS names its
    /// own. With Include Device Frame it is drawn inside Pane's frame. The pill says where.
    func saveScreenshot() {
        let folder = Self.captureFolder
        captureScreenshot { [weak self] png in
            let url = try Self.writeScreenshot(png, in: folder)
            self?.log.info("Saved screenshot \(url.lastPathComponent, privacy: .public)")
            return .saved(to: folder)
        }
    }

    /// Writes the PNG to a temporary folder and opens it in Preview, as macOS's Preview target
    /// does. Preview comes forward; Pane's windows stay where they are.
    private func previewScreenshot() {
        let folder = FileManager.default.temporaryDirectory.appending(
            path: Self.previewFolderName, directoryHint: .isDirectory)
        captureScreenshot { [weak self] png in
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = try Self.writeScreenshot(png, in: folder)
            let workspace = NSWorkspace.shared
            if let preview = workspace.urlForApplication(withBundleIdentifier: Self.previewBundleID) {
                workspace.open([url], withApplicationAt: preview, configuration: NSWorkspace.OpenConfiguration())
            } else {
                workspace.open(url)
            }
            self?.log.info("Opened screenshot \(url.lastPathComponent, privacy: .public) in Preview")
            return nil
        }
    }

    private static func writeScreenshot(_ png: Data, in folder: URL) throws -> URL {
        let url = CaptureFileName.unusedURL(in: folder, prefix: "Pane", date: Date(), fileExtension: "png")
        try png.write(to: url, options: .withoutOverwriting)
        return url
    }

    private static let previewBundleID = "com.apple.Preview"
    private static let previewFolderName = "Pane Screenshots"

    /// Puts a full-size PNG of the screen on the Mac's clipboard.
    func copyScreenshot() {
        captureScreenshot { [weak self] png in
            let pasteboard = Self.pasteboard
            pasteboard.clearContents()
            pasteboard.setData(png, forType: .png)
            self?.noteOwnPasteboardWrite()
            self?.log.info("Copied screenshot")
            return .copied
        }
    }

    /// Takes the screenshot and hands it to `use`, which returns the pill's words (nil for
    /// none). One at a time: a press while the frame is on its way is ignored, and Screenshot
    /// stays pressed until it arrives. Then the screen flashes (`CaptureFlash`), the press
    /// shade lets go, and the pill shows once the PNG is written or copied. On failure Pane
    /// beeps and the pill says so, with no flash when no frame came.
    private func captureScreenshot(then use: @escaping @MainActor (Data) throws -> CaptureNotice?) {
        guard let connection, status == .live, captureGate.begin() else { return }
        let framed = settings.includesDeviceFrame
        let quadrants = quadrants
        let spec = frameSpec
        let style = Theme.Frame.exportStyle(appearance: screenView.effectiveAppearance)
        Task { [weak self] in
            var arrived = false
            do {
                #if DEBUG
                    // `-PaneScreenshotDelay <seconds>` holds the frame back, so checks can see the
                    // in-flight state (pressed, a second press ignored).
                    let delay = UserDefaults.standard.double(forKey: "PaneScreenshotDelay")
                    if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
                #endif
                let shot = try await connection.screenshotPNG()
                arrived = true
                self?.captureGate.finish()
                self?.captureFlashes += 1
                let png = framed ? try await Self.framedPNG(shot, spec: spec, quadrants: quadrants, style: style) : shot
                if let line = try use(png) { self?.showNotice(line) }
            } catch {
                self?.log.error("Screenshot failed: \(String(describing: error), privacy: .public)")
                if !arrived { self?.captureGate.finish() }
                self?.showProblem(.screenshotFailed)
            }
        }
    }

    /// Draws the frame around a screenshot, off the main actor.
    private nonisolated static func framedPNG(
        _ png: Data, spec: FrameSpec, quadrants: Int, style: ReadOnlyBox<FrameStyle>
    ) async throws -> Data {
        guard let shot = FramedScreenshot.image(fromPNG: png),
            let image = FramedScreenshot.render(
                screenshot: shot, spec: spec, quadrants: quadrants, style: style.value),
            let data = FramedScreenshot.png(from: image)
        else { throw CaptureProblem.cannotDrawFrame }
        return data
    }

    private enum CaptureProblem: Error {
        case cannotDrawFrame
    }

    // MARK: GIF export

    /// Writes a recording as a GIF beside it, with the same name.
    func exportGIF(from movie: URL) {
        guard exportTask == nil else { return }
        let gif = CaptureFileName.unusedSibling(of: movie, fileExtension: "gif")
        log.info("Exporting \(movie.lastPathComponent, privacy: .public) as GIF")
        showNotice("Exporting GIF…", busy: true)
        exportTask = Task { [weak self] in
            do {
                let frames = try await Task.detached {
                    try await GifExporter.export(movie: movie, to: gif, options: Theme.Export.gif)
                }.value
                self?.log.info("Saved \(gif.lastPathComponent, privacy: .public), \(frames) frames")
                self?.showNotice("Saved GIF.")
            } catch is CancellationError {
                self?.showNotice("Export stopped.")
            } catch {
                self?.log.error("GIF export failed: \(String(describing: error), privacy: .public)")
                self?.showProblem("The GIF couldn't be made.")
            }
            self?.exportTask = nil
        }
    }

    // MARK: Open Link

    /// Opens a link on the device (`am start`, VIEW). Returns nil when it opened, else one
    /// short line saying why not. A link that opened joins this AVD's Recent list.
    func openLink(_ text: String) async -> String? {
        let link: String
        do {
            link = try DeviceLink.validated(text)
        } catch {
            return error.message
        }
        guard status == .live, let emulator, let adb = Adb(emulator: emulator) else { return "No emulator connected." }
        do {
            let output = try await adb.run(DeviceLink.arguments(for: link))
            if let failure = DeviceLink.failure(in: output) {
                log.error("Open link failed: \(failure, privacy: .public)")
                return failure
            }
        } catch let failure as Adb.Failure {
            return failure.message
        } catch {
            log.error("Open link failed: \(String(describing: error), privacy: .public)")
            return "adb didn't run."
        }
        log.info("Opened a link")
        settings.addRecentLink(link, for: emulator.avdName)
        return nil
    }

    var recentLinks: [String] {
        (emulator?.avdName).map { settings.recentLinks(for: $0).links } ?? []
    }

    // MARK: Appearance, text size, location

    /// Just connected: read what the menus tick and put back this AVD's custom location.
    func deviceBecameLive() {
        refreshDeviceSettings()
        if let location = customLocation { applyLocation(location) }
    }

    /// Reads the device's theme and text size for the menus' ticks.
    func refreshDeviceSettings() {
        guard status == .live, let emulator, let adb = Adb(emulator: emulator), let connection else { return }
        Task { [weak self] in
            let appearance = try? await adb.run(DeviceAppearance.getArguments)
            let textSize = try? await adb.run(DeviceTextSize.getArguments)
            guard let self, self.connection === connection else { return }
            self.deviceAppearance = appearance.flatMap { DeviceAppearance.parse($0.text) }
            self.deviceTextSize = textSize.flatMap { DeviceTextSize.parse($0.text) }
        }
    }

    func setAppearance(_ appearance: DeviceAppearance) {
        runSetting(appearance.setArguments) { $0.deviceAppearance = appearance }
    }

    func setTextSize(_ size: DeviceTextSize) {
        runSetting(size.setArguments) { $0.deviceTextSize = size }
    }

    private func runSetting(_ arguments: [String], then apply: @escaping @MainActor (PaneModel) -> Void) {
        guard status == .live, let emulator, let adb = Adb(emulator: emulator) else { return }
        Task { [weak self] in
            do {
                let output = try await adb.run(arguments)
                guard let self else { return }
                if output.status == 0 {
                    apply(self)
                } else {
                    let reason = Adb.shortReason(from: output.text)
                    self.log.error("Setting failed: \(reason, privacy: .public)")
                    self.showProblem(reason.isEmpty ? "The device didn't take the change." : reason)
                }
                self.refreshDeviceSettings()
            } catch {
                self?.showProblem((error as? Adb.Failure)?.message ?? "adb didn't run.")
            }
        }
    }

    /// The custom location remembered for the AVD on screen; nil is Location ▸ Default.
    var customLocation: DeviceLocation? {
        (emulator?.avdName).flatMap(settings.location(for:))
    }

    /// Location ▸ Custom…: moves the device's GPS there and remembers it for this AVD.
    /// Location ▸ Default (nil): forgets it and puts the GPS back where the emulator starts.
    func setCustomLocation(_ location: DeviceLocation?) {
        guard let emulator else { return }
        settings.setLocation(location, for: emulator.avdName)
        applyLocation(location ?? .emulatorDefault)
    }

    private func applyLocation(_ location: DeviceLocation) {
        guard let connection else { return }
        Task { [weak self] in
            do {
                try await connection.setLocation(location)
                self?.log.info("Location set")
                #if DEBUG
                    // Lets a check confirm what the emulator now reports.
                    let now = try await connection.location()
                    self?.log.info("Emulator GPS reads \(now.summary, privacy: .public)")
                #endif
            } catch {
                self?.log.error("Location not set: \(String(describing: error), privacy: .public)")
                self?.showProblem("The location didn't change.")
            }
        }
    }
}

/// Lets a value that isn't `Sendable` (Core Graphics colours) cross into a detached task that
/// only reads it.
struct ReadOnlyBox<Value>: @unchecked Sendable {
    let value: Value
}
