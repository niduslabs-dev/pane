import Foundation

/// Open Link: checks what was typed and builds the `am start` call that opens it on the device.
public enum DeviceLink {
    public enum Problem: Error, Equatable, Sendable {
        case empty
        case controlCharacters
        case noScheme

        /// One short line for the sheet.
        public var message: String {
            switch self {
            case .empty: "Enter a link."
            case .controlCharacters: "The link has characters that can't be sent."
            case .noScheme: "Start the link with a scheme, like https://."
            }
        }
    }

    /// The link to send: trimmed, with no control characters (a newline or escape could start a
    /// second command in the device's shell) and with a scheme, so Android can route it.
    public static func validated(_ text: String) throws(Problem) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .empty }
        guard !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw .controlCharacters
        }
        guard let colon = trimmed.firstIndex(of: ":"), colon != trimmed.startIndex,
            trimmed[..<colon].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "+-.".contains($0)) }),
            trimmed[trimmed.startIndex].isLetter
        else { throw .noScheme }
        return trimmed
    }

    /// `adb shell am start -a android.intent.action.VIEW -d <link>` as an argument array. The
    /// link is single-quoted for the device's shell, which `adb shell` hands its arguments to.
    public static func arguments(for link: String) -> [String] {
        ["shell", "am", "start", "-a", "android.intent.action.VIEW", "-d", Adb.deviceShellQuoted(link)]
    }

    /// Nil when `am start` opened the link; otherwise its reason in one short line. `am` can
    /// print "Error: …" and still exit 0, so the text is checked too.
    public static func failure(in output: Adb.Output) -> String? {
        let lines = output.text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        let errorLine = lines.first { $0.hasPrefix("Error:") || $0.hasPrefix("error:") }
        guard output.status != 0 || errorLine != nil else { return nil }
        if let errorLine, errorLine.contains("unable to resolve Intent") {
            return "No app on the device opens this link."
        }
        let reason = Adb.shortReason(from: errorLine ?? output.text)
        return reason.isEmpty ? "The link didn't open." : reason
    }
}

/// The links opened lately on one AVD, newest first, for the Open Link sheet's Recent list.
public struct RecentLinks: Sendable, Equatable {
    public static let limit = 8

    public private(set) var links: [String]

    public init(_ links: [String] = []) {
        self.links = Array(links.prefix(Self.limit))
    }

    /// Puts `link` first, dropping an older copy of it and anything past the limit.
    public mutating func add(_ link: String) {
        links.removeAll { $0 == link }
        links.insert(link, at: 0)
        if links.count > Self.limit { links.removeLast(links.count - Self.limit) }
    }
}
