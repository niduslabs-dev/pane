/// Decides when text moves between the Mac's clipboard and the device's.
///
/// Text only, and only while Pane's window is key: something copied elsewhere on the Mac (a
/// password, say) never reaches the device unless the user pastes it into Pane. Each side's
/// last text is remembered so a copy isn't bounced straight back.
public struct ClipboardSync: Sendable, Equatable {
    public enum Action: Sendable, Equatable {
        case setDevice(String)
        case setMac(String)
    }

    /// The text last sent to, or received from, the device.
    private var deviceText: String?

    public init() {}

    /// The Mac's clipboard changed (seen while polling, so only ever while the window is key).
    public mutating func macChanged(to text: String?, isKey: Bool, isEnabled: Bool) -> Action? {
        guard isEnabled, isKey, let text, !text.isEmpty, text != deviceText else { return nil }
        deviceText = text
        return .setDevice(text)
    }

    /// Paste in Pane's window: the Mac's text goes to the device first, even when unchanged
    /// since Pane became key. Nil when the device already has it.
    public mutating func pasteRequested(macText text: String?, isEnabled: Bool) -> Action? {
        guard isEnabled, let text, !text.isEmpty, text != deviceText else { return nil }
        deviceText = text
        return .setDevice(text)
    }

    /// What the device's clipboard held when the connection opened (read with `getClipboard`
    /// before the stream starts). It isn't a change, so it never goes to the Mac. The stream
    /// can't be trusted for this: it repeats the current state first only when there is one.
    public mutating func deviceBaseline(_ text: String) { deviceText = text }

    /// The device's clipboard stream sent text.
    public mutating func deviceChanged(to text: String, isKey: Bool, isEnabled: Bool) -> Action? {
        let changed = text != deviceText
        deviceText = text
        guard isEnabled, isKey, changed, !text.isEmpty else { return nil }
        return .setMac(text)
    }

    /// A new connection: the baseline is read again.
    public mutating func reset() { self = ClipboardSync() }
}
