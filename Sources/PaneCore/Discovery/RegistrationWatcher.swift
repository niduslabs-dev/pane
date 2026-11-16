import Darwin
import Foundation

/// Calls back whenever an entry is added to, removed from or renamed in the registration
/// folder, so the window notices an emulator starting or stopping without polling.
///
/// A kqueue vnode source on the folder itself. If the folder doesn't exist yet (no emulator has
/// run since login), `start()` returns false and the caller shows the no-emulator state.
public final class RegistrationWatcher: @unchecked Sendable {
    // Unchecked: `source` is only touched from `queue`, which serializes start, stop and events.
    private let directory: URL
    private let queue = DispatchQueue(label: "dev.niduslabs.pane.registration-watcher")
    private var source: (any DispatchSourceFileSystemObject)?
    private let onChange: @Sendable () -> Void

    public init(directory: URL = EmulatorDiscovery.registrationDirectory(), onChange: @escaping @Sendable () -> Void) {
        self.directory = directory
        self.onChange = onChange
    }

    deinit {
        source?.cancel()
    }

    /// Starts watching; false when the folder can't be opened.
    @discardableResult
    public func start() -> Bool {
        queue.sync {
            guard source == nil else { return true }
            let descriptor = open(directory.path, O_EVTONLY)
            guard descriptor >= 0 else { return false }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor, eventMask: [.write, .delete, .rename], queue: queue)
            let onChange = onChange
            source.setEventHandler { onChange() }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            self.source = source
            return true
        }
    }

    public func stop() {
        queue.sync {
            source?.cancel()
            source = nil
        }
    }
}
