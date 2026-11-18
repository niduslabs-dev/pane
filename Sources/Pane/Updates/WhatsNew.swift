import Foundation

/// What's new's data for Pane: the kit's `ReleaseNotesSheet` draws it.
extension UpdateModel {
    /// The tag on the pending update once it is downloaded and checked.
    static let readyTag = "Ready to install"
    /// The tag on the running version.
    static let installedTag = "Installed"

    /// What's new, newest first: the pending update from the feed (when there is one), then
    /// the running version and every older one from the bundled RELEASE_NOTES.md
    /// (`scripts/build-app.sh` copies it in). Sections newer than the running version (a
    /// build made before its release) are left out.
    func whatsNew(bundled: [ReleaseNotesFile.Section]) -> [ReleaseNoteGroup] {
        var groups: [ReleaseNoteGroup] = []
        if let update, ReleaseNotesFile.isNewer(update.version, than: currentVersion), !update.notes.isEmpty {
            let ready: Bool
            switch phase {
            case .ready, .installing: ready = true
            case .idle, .checking, .available, .downloading, .upToDate, .failed: ready = false
            }
            groups.append(
                ReleaseNoteGroup(version: update.version, tag: ready ? Self.readyTag : nil, lines: update.notes))
        }
        for section in bundled
        where !section.lines.isEmpty && !ReleaseNotesFile.isNewer(section.version, than: currentVersion) {
            groups.append(
                ReleaseNoteGroup(
                    version: section.version, tag: section.version == currentVersion ? Self.installedTag : nil,
                    lines: section.lines))
        }
        return groups
    }

    /// Where What's new's All release notes goes.
    static let allReleaseNotesURL = URL(string: "https://niduslabs.dev/pane/releases")!
}

extension VersionRowState {
    /// The kit row's content (`UpdateRow`).
    var content: UpdateRowContent {
        UpdateRowContent(
            title: title, caption: caption, percent: percent, lead: spinner ? .spinner : .none, isError: isError,
            button: actionTitle, buttonKind: actionIsPrimary ? .primary : .secondary, buttonEnabled: actionEnabled,
            buttonAccessibilityLabel: actionAccessibilityLabel, showsWhatsNew: showsWhatsNew,
            whatsNewAccessibilityLabel: whatsNewAccessibilityLabel)
    }
}
