import AppKit
import PaneCore
import SwiftUI

/// The sheet's frame (design guide, Sheet; board 8): a title, one line of description, the
/// body, and Cancel and the primary action at the bottom right. Esc cancels, Return runs the
/// primary.
struct SheetScaffold<Content: View>: View {
    let title: String
    let description: String
    let primaryTitle: String
    let primaryDisabled: Bool
    let onCancel: () -> Void
    let onPrimary: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(Theme.Typeface.sheetTitle)
                .foregroundStyle(Color(nsColor: Theme.Palette.text))
                .accessibilityAddTraits(.isHeader)
            Text(description)
                .font(Theme.Typeface.sheetBody)
                .foregroundStyle(Color(nsColor: Theme.Palette.textSecondary))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Sheet.descriptionGap)
            content
                .padding(.top, Theme.Sheet.bodyGap)
            HStack(spacing: Theme.Sheet.buttonGap) {
                Spacer(minLength: 0)
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

/// The secondary capsule (design guide, Button): a raised surface with a hairline.
struct SecondaryCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typeface.sheetSecondary)
            .foregroundStyle(Color(nsColor: Theme.Palette.text))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, Theme.Capsule.standardPadding)
            .frame(height: Theme.Capsule.height)
            .background(Capsule().fill(Color(nsColor: Theme.Palette.secondaryAction)))
            .overlay(Capsule().strokeBorder(Color(nsColor: Theme.Palette.hairline), lineWidth: Theme.Sheet.fieldBorder))
            .overlay(
                Capsule().fill(
                    Color(nsColor: Theme.Palette.shade).opacity(
                        configuration.isPressed ? Theme.Toolbar.pressedOpacity : 0))
            )
            .contentShape(Capsule())
    }
}

/// A one-line text field on a sheet (a value control: radius 8). Focused, it has the moss
/// ring; with a problem, a red one and the problem in one line under it.
struct SheetField: View {
    let label: String
    var showsLabel = true
    let placeholder: String
    @Binding var text: String
    var problem: String?
    var onSubmit: () -> Void = {}
    @FocusState private var isFocused: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Sheet.fieldRadius, style: .continuous)
        let ring = problem != nil ? Theme.Palette.problemText : (isFocused ? Theme.Palette.fieldFocus : nil)
        let halo = problem != nil ? Theme.Palette.problemHalo : Theme.Palette.fieldFocusHalo
        VStack(alignment: .leading, spacing: Theme.Sheet.fieldLabelGap) {
            if showsLabel {
                Text(label)
                    .font(Theme.Typeface.sheetLabel)
                    .foregroundStyle(Color(nsColor: Theme.Palette.textSecondary))
                    .accessibilityHidden(true)
            }
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(Theme.Typeface.sheetBody)
                .foregroundStyle(Color(nsColor: Theme.Palette.text))
                .focused($isFocused)
                .onSubmit(onSubmit)
                .padding(.horizontal, Theme.Sheet.fieldPaddingH)
                .frame(height: Theme.Sheet.fieldHeight)
                .background(shape.fill(Color(nsColor: Theme.Palette.fieldSurface)))
                .overlay(
                    shape.strokeBorder(
                        Color(nsColor: ring ?? Theme.Palette.hairline),
                        lineWidth: ring == nil
                            ? Kit.hairlineWidth(Theme.Sheet.hairline, contrast: contrast) : Theme.Sheet.fieldBorder)
                )
                .background(
                    shape.inset(by: -Theme.Sheet.fieldHalo)
                        .fill(Color(nsColor: halo).opacity(ring == nil ? 0 : 1))
                )
                .accessibilityLabel(label)
            if let problem {
                Text(problem)
                    .font(Theme.Typeface.sheetRecent)
                    .foregroundStyle(Color(nsColor: Theme.Palette.problemText))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("sheet.problem")
            }
        }
    }
}

/// Open link (board 8): a field, the links opened lately on this emulator, and Cancel and
/// Open. While Android answers, the field dims and Open is disabled in place. A link that
/// doesn't open leaves the sheet up with one red line under the field.
struct OpenLinkSheet: View {
    let model: PaneModel
    let close: () -> Void
    @State var text: String
    @State private var problem: String?
    @State private var isOpening = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        SheetScaffold(
            title: "Open link", description: "Opens on the device. Web links and app links both work.",
            primaryTitle: "Open", primaryDisabled: isOpening || text.trimmingCharacters(in: .whitespaces).isEmpty,
            onCancel: close, onPrimary: open
        ) {
            VStack(alignment: .leading, spacing: 0) {
                SheetField(
                    label: "Link", showsLabel: false, placeholder: "https:// or myapp://", text: $text,
                    problem: problem, onSubmit: open
                )
                .focused($fieldFocused)
                .disabled(isOpening)
                .opacity(isOpening ? Theme.Sheet.busyOpacity : 1)
                let recent = model.recentLinks
                if !recent.isEmpty {
                    Text("Recent")
                        .font(Theme.Typeface.sheetLabel)
                        .foregroundStyle(Color(nsColor: Theme.Palette.textSecondary))
                        .padding(.leading, Theme.Sheet.recentLabelInset)
                        .padding(.top, Theme.Sheet.bodyGap)
                    VStack(alignment: .leading, spacing: Theme.Sheet.listGap) {
                        ForEach(recent, id: \.self) { link in
                            RecentLinkRow(link: link) {
                                // A recent link fills the field and opens.
                                text = link
                                open()
                            }
                        }
                    }
                    .padding(Theme.Sheet.cardInset)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Sheet.cardRadius, style: .continuous)
                            .fill(Color(nsColor: Theme.Palette.sheetCard))
                    )
                    .overlay(
                        Hairline(
                            shape: RoundedRectangle(cornerRadius: Theme.Sheet.cardRadius, style: .continuous),
                            width: Theme.Sheet.hairline, colour: Color(nsColor: Theme.Palette.hairline))
                    )
                    .padding(.top, Theme.Sheet.fieldLabelGap)
                    .disabled(isOpening)
                }
            }
        }
        .onAppear { fieldFocused = true }
        .onChange(of: text) { problem = nil }
    }

    private func open() {
        guard !isOpening else { return }
        isOpening = true
        let link = text
        Task {
            let failure = await model.openLink(link)
            isOpening = false
            if let failure {
                problem = failure
                fieldFocused = true
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
                .font(Theme.Typeface.sheetRecentLink)
                .foregroundStyle(Color(nsColor: Theme.Palette.text))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Sheet.rowPaddingH)
                .padding(.vertical, Theme.Sheet.rowPaddingV)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Sheet.rowRadius, style: .continuous)
                        .fill(Color(nsColor: Theme.Palette.menuHighlight).opacity(hovered ? 1 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plainRow)
        .onHover { hovered = $0 }
        .accessibilityLabel(link)
        .accessibilityHint("Opens this link.")
    }
}

/// Location ▸ Custom… (board 7, "Set location"): latitude and longitude in degrees. Set
/// Location stays disabled in place until both are valid numbers in range.
struct LocationSheet: View {
    let model: PaneModel
    let close: () -> Void
    @State var latitude: String
    @State var longitude: String
    @FocusState private var latitudeFocused: Bool

    var body: some View {
        SheetScaffold(
            title: "Set location", description: "The device reports this place until you choose Default.",
            primaryTitle: "Set location", primaryDisabled: location == nil, onCancel: close, onPrimary: set
        ) {
            HStack(alignment: .top, spacing: Theme.Sheet.fieldPairGap) {
                SheetField(label: "Latitude", placeholder: "12.9716", text: $latitude, onSubmit: set)
                    .focused($latitudeFocused)
                SheetField(label: "Longitude", placeholder: "77.5946", text: $longitude, onSubmit: set)
            }
        }
        .onAppear { latitudeFocused = true }
    }

    private var location: DeviceLocation? { DeviceLocation(latitudeText: latitude, longitudeText: longitude) }

    private func set() {
        guard let location else { return }
        model.setCustomLocation(location)
        close()
    }
}

/// A confirmation (design guide, Sheet / Confirmation): content-sized, Cancel and one action
/// that says what happens. Esc always cancels. For a destructive action (`confirmDestructive`,
/// Button's destructive variant) the safe choice leads: Cancel is the moss primary, rightmost
/// and the default (Return), and the action is a secondary capsule that takes a click, or
/// Space once Tab has reached it. Otherwise the action is the moss primary and Return runs it.
/// `content` is the Sheet's optional body.
struct ConfirmSheet<Content: View>: View {
    let title: String
    let detail: String
    let action: String
    var isDestructive = true
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(Theme.Typeface.sheetTitle)
                .foregroundStyle(Color(nsColor: Theme.Palette.text))
                .accessibilityAddTraits(.isHeader)
            Text(detail)
                .font(Theme.Typeface.sheetBody)
                .foregroundStyle(Color(nsColor: Theme.Palette.textSecondary))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Sheet.descriptionGap)
            content
                .padding(.top, Theme.Sheet.bodyGap)
            HStack(spacing: Theme.Sheet.buttonGap) {
                Spacer(minLength: 0)
                if isDestructive {
                    Button(action, action: onConfirm)
                        .buttonStyle(.nidusSecondary)
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.nidusPrimary)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.nidusSecondary)
                    Button(action, action: onConfirm)
                        .buttonStyle(.nidusPrimary)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.top, Theme.Sheet.footerGap)
        }
        .padding(Theme.Sheet.inset)
        .frame(width: Theme.Sheet.width, alignment: .leading)
        .background(Color(nsColor: Theme.Palette.sheetSurface))
        .onExitCommand(perform: onCancel)
    }
}

extension ConfirmSheet where Content == EmptyView {
    init(
        title: String, detail: String, action: String, isDestructive: Bool = true, onCancel: @escaping () -> Void,
        onConfirm: @escaping () -> Void
    ) {
        self.init(
            title: title, detail: detail, action: action, isDestructive: isDestructive, onCancel: onCancel,
            onConfirm: onConfirm, content: { EmptyView() })
    }
}

/// Export Recording as GIF… when there is a last recording: a confirmation whose body is one
/// row naming the recording, with Choose another… to pick any movie instead. Export is the
/// primary and Return runs it; Esc cancels.
struct ExportGIFSheet: View {
    let recording: URL
    let close: () -> Void
    let export: () -> Void
    let chooseAnother: () -> Void

    var body: some View {
        ConfirmSheet(
            title: "Export recording as GIF", detail: "The GIF is saved next to the recording.",
            action: "Export", isDestructive: false, onCancel: close,
            onConfirm: confirm, content: { row })
    }

    private func confirm() {
        close()
        export()
    }

    private var row: some View {
        Group {
            let shape = RoundedRectangle(cornerRadius: Theme.Sheet.cardRadius, style: .continuous)
            // The name has the row's whole width, over Choose another…, so the date and time
            // that tell recordings apart stay visible. Past two lines it is cut in the middle
            // (`noWrapLabel`, file names).
            VStack(alignment: .leading, spacing: Theme.Sheet.descriptionGap) {
                Text(recording.lastPathComponent)
                    .font(Theme.Typeface.sheetBody)
                    .foregroundStyle(Color(nsColor: Theme.Palette.text))
                    .lineLimit(Theme.Sheet.fileNameLines)
                    .truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Choose another\u{2026}") {
                    close()
                    chooseAnother()
                }
                .buttonStyle(.nidusSmall)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Sheet.rowPaddingH)
            .padding(.vertical, Theme.Sheet.rowPaddingV)
            .background(shape.fill(Color(nsColor: Theme.Palette.sheetCard)))
            .overlay(Hairline(shape: shape, colour: Color(nsColor: Theme.Palette.hairline)))
        }
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
        let hosting = NSHostingController(rootView: content(close).displayOptions())
        hosting.sizingOptions = [.preferredContentSize]
        sheet.contentViewController = hosting
        sheet.setContentSize(hosting.view.fittingSize)
        window.beginSheet(sheet)
        return sheet
    }

    /// A confirmation as a Nidus sheet (board 5): the question, what it costs, Cancel and the
    /// moss action. Cancel is the default, so Return never runs the action by accident.
    @discardableResult
    static func confirm(
        on window: NSWindow, message: String, detail: String, action: String, then run: @escaping @MainActor () -> Void
    ) -> NSWindow {
        present(on: window) { close in
            ConfirmSheet(
                title: message, detail: detail, action: action, onCancel: close,
                onConfirm: {
                    close()
                    run()
                })
        }
    }

}
