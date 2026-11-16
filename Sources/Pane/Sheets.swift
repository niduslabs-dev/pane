import AppKit
import PaneCore
import SwiftUI

/// The sheet's frame (design guide, Sheet): a title, one line of description, the body, and
/// Cancel and the primary action at the bottom right. Esc cancels, Return runs the primary.
struct SheetScaffold<Content: View>: View {
    let title: String
    let description: String
    let primaryTitle: String
    let primaryDisabled: Bool
    let problem: String?
    let onCancel: () -> Void
    let onPrimary: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(Theme.Typeface.sheetTitle)
                .foregroundStyle(Color(nsColor: Theme.Palette.text))
            Text(description)
                .font(Theme.Typeface.sheetBody)
                .foregroundStyle(Color(nsColor: Theme.Palette.textSecondary))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Sheet.descriptionGap)
            content
                .padding(.top, Theme.Sheet.bodyGap)
            HStack(spacing: Theme.Sheet.buttonGap) {
                if let problem {
                    Text(problem)
                        .font(Theme.Typeface.cardBody)
                        .foregroundStyle(Color(nsColor: Theme.Palette.problemText))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .accessibilityIdentifier("sheet.problem")
                }
                Spacer(minLength: Theme.Sheet.problemGap)
                Button("Cancel", action: onCancel)
                    .buttonStyle(SecondaryCapsuleButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button(primaryTitle, action: onPrimary)
                    .buttonStyle(CapsuleButtonStyle(horizontalPadding: Theme.Capsule.standardPadding))
                    .keyboardShortcut(.defaultAction)
                    .disabled(primaryDisabled)
            }
            .padding(.top, Theme.Sheet.footerGap)
        }
        .padding(Theme.Sheet.inset)
        .frame(width: Theme.Sheet.width, alignment: .leading)
        .background(Color(nsColor: Theme.Palette.sheetSurface))
    }
}

/// The secondary capsule (design guide, Button): the card surface with a hairline.
struct SecondaryCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typeface.capsule)
            .foregroundStyle(Color(nsColor: Theme.Palette.text))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, Theme.Capsule.standardPadding)
            .frame(height: Theme.Capsule.height)
            .background(Capsule().fill(Color(nsColor: Theme.Palette.secondaryAction)))
            .overlay(Capsule().strokeBorder(Color(nsColor: Theme.Palette.hairline), lineWidth: Theme.Sheet.hairline))
            .overlay(
                Capsule().fill(
                    Color(nsColor: Theme.Palette.shade).opacity(
                        configuration.isPressed ? Theme.Toolbar.pressedOpacity : 0))
            )
            .contentShape(Capsule())
    }
}

/// A one-line text field on a sheet (a value control: radius 8).
struct SheetField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Sheet.fieldLabelGap) {
            Text(label)
                .font(Theme.Typeface.sheetLabel)
                .foregroundStyle(Color(nsColor: Theme.Palette.textSecondary))
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(Theme.Typeface.sheetBody)
                .foregroundStyle(Color(nsColor: Theme.Palette.text))
                .onSubmit(onSubmit)
                .padding(.horizontal, Theme.Sheet.fieldPaddingH)
                .frame(height: Theme.Sheet.fieldHeight)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Sheet.fieldRadius, style: .continuous)
                        .fill(Color(nsColor: Theme.Palette.fieldSurface))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Sheet.fieldRadius, style: .continuous)
                        .strokeBorder(Color(nsColor: Theme.Palette.hairline), lineWidth: Theme.Sheet.hairline)
                )
                .accessibilityLabel(label)
        }
    }
}

/// Open Link: a field, the links opened lately on this emulator, and Cancel and Open. A link
/// that doesn't open leaves the sheet up with adb's reason in one line.
struct OpenLinkSheet: View {
    let model: PaneModel
    let close: () -> Void
    @State var text: String
    @State private var problem: String?
    @State private var isOpening = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        SheetScaffold(
            title: "Open Link", description: "Opens on the device. Web links and app links both work.",
            primaryTitle: "Open", primaryDisabled: isOpening || text.trimmingCharacters(in: .whitespaces).isEmpty,
            problem: problem, onCancel: close, onPrimary: open
        ) {
            VStack(alignment: .leading, spacing: Theme.Sheet.bodyGap) {
                SheetField(label: "Link", placeholder: "https://", text: $text, onSubmit: open)
                    .focused($fieldFocused)
                let recent = model.recentLinks
                if !recent.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Sheet.fieldLabelGap) {
                        Text("Recent")
                            .font(Theme.Typeface.sheetLabel)
                            .foregroundStyle(Color(nsColor: Theme.Palette.textSecondary))
                        VStack(alignment: .leading, spacing: Theme.Sheet.listGap) {
                            ForEach(recent, id: \.self) { link in
                                RecentLinkRow(link: link) {
                                    text = link
                                    problem = nil
                                }
                            }
                        }
                    }
                }
            }
        }
        .onAppear { fieldFocused = true }
        .onChange(of: text) { problem = nil }
    }

    private func open() {
        guard !isOpening else { return }
        isOpening = true
        Task {
            let failure = await model.openLink(text)
            isOpening = false
            if let failure {
                problem = failure
            } else {
                close()
            }
        }
    }
}

private struct RecentLinkRow: View {
    let link: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(link)
                .font(Theme.Typeface.sheetBody)
                .foregroundStyle(hovered ? Color.white : Color(nsColor: Theme.Palette.text))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Sheet.rowPaddingH)
                .frame(height: Theme.Sheet.rowHeight)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Sheet.rowRadius, style: .continuous)
                        .fill(hovered ? Color(nsColor: .selectedContentBackgroundColor) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel(link)
    }
}

/// Location ▸ Custom…: latitude and longitude in degrees.
struct LocationSheet: View {
    let model: PaneModel
    let close: () -> Void
    @State var latitude: String
    @State var longitude: String
    @State private var problem: String?
    @FocusState private var latitudeFocused: Bool

    var body: some View {
        SheetScaffold(
            title: "Custom Location", description: "Moves the device's GPS. Remembered for this emulator.",
            primaryTitle: "Set Location", primaryDisabled: latitude.isEmpty || longitude.isEmpty, problem: problem,
            onCancel: close, onPrimary: set
        ) {
            HStack(alignment: .top, spacing: Theme.Sheet.fieldPairGap) {
                SheetField(label: "Latitude", placeholder: "12.9716", text: $latitude, onSubmit: set)
                    .focused($latitudeFocused)
                SheetField(label: "Longitude", placeholder: "77.5946", text: $longitude, onSubmit: set)
            }
        }
        .onAppear { latitudeFocused = true }
    }

    private func set() {
        guard let location = DeviceLocation(latitudeText: latitude, longitudeText: longitude) else {
            problem = "Latitude is −90 to 90. Longitude is −180 to 180."
            return
        }
        model.setCustomLocation(location)
        close()
    }
}

/// Shows SwiftUI content as a sheet on a window.
@MainActor
enum SheetPresenter {
    /// Presents `content` (built with a closure that closes the sheet) and returns the sheet.
    @discardableResult
    static func present<Content: View>(on window: NSWindow, @ViewBuilder content: (@escaping () -> Void) -> Content)
        -> NSWindow
    {
        let sheet = NSWindow(
            contentRect: .zero, styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        sheet.titleVisibility = .hidden
        sheet.titlebarAppearsTransparent = true
        sheet.isReleasedWhenClosed = false
        let close = { [weak window, weak sheet] in
            guard let window, let sheet, sheet.sheetParent != nil else { return }
            window.endSheet(sheet)
        }
        let hosting = NSHostingController(rootView: content(close))
        hosting.sizingOptions = [.preferredContentSize]
        sheet.contentViewController = hosting
        sheet.setContentSize(hosting.view.fittingSize)
        window.beginSheet(sheet)
        return sheet
    }

    /// A confirmation with a destructive action that isn't the default (Return cancels).
    static func confirm(
        on window: NSWindow, message: String, detail: String, action: String, then run: @escaping @MainActor () -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        let button = alert.addButton(withTitle: action)
        button.hasDestructiveAction = true
        button.keyEquivalent = ""
        let cancel = alert.addButton(withTitle: "Cancel")
        cancel.keyEquivalent = "\r"
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn { run() }
        }
    }
}
