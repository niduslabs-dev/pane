import AppKit
import PaneCore
import SwiftUI

/// The drop's layer over the device screen: the dim and the moss outline while a drop is taken
/// or runs, and the one card (the drag card while files hover, the result card after). The card
/// stays inside the screen, so it never covers the toolbar, the title or the frame buttons; a
/// refused drag's card sits at the top, clear of the no-emulator screen's Start.
struct DropLayer: View {
    let drop: DropModel
    let screenRadius: CGFloat

    var body: some View {
        let dims = drop.dimsScreen
        let refused = drop.drag?.card.isRefused ?? false
        ZStack(alignment: .top) {
            if dims {
                Color(nsColor: Theme.Palette.dropScrim)
                    // Over the running or finished card's dim, clicks stay off the device.
                    .contentShape(Rectangle())
                    .accessibilityHidden(true)
                RoundedRectangle(cornerRadius: screenRadius)
                    .strokeBorder(
                        Color(nsColor: Theme.Palette.toolHalo),
                        lineWidth: Theme.Drop.outlineWidth + Theme.Drop.haloWidth
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: screenRadius)
                            .strokeBorder(Color(nsColor: Theme.Palette.toolSelect), lineWidth: Theme.Drop.outlineWidth)
                    )
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            if drop.showsCard {
                card
                    .padding(.horizontal, Theme.Drop.sideMargin)
                    .padding(.top, refused ? Theme.Drop.refusedTop : Theme.Drop.sideMargin)
                    .padding(.bottom, Theme.Drop.sideMargin)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: refused ? .top : .center)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: Theme.Drop.fadeDuration), value: dims)
        .animation(.easeOut(duration: Theme.Drop.fadeDuration), value: drop.showsCard)
        // The drag card takes no clicks (nothing can be clicked mid-drag); the result card and
        // its dim do.
        .allowsHitTesting(drop.drag == nil && drop.job != nil && !drop.isHidden)
    }

    @ViewBuilder private var card: some View {
        if let drag = drop.drag {
            DragCardView(drag: drag, icons: drag.items.filter(\.isApp).compactMap { drop.icons[$0.url] })
        } else if let job = drop.job {
            DropResultCard(drop: drop, job: job)
        }
    }
}

/// The card's surface: the notification panel's anatomy inside the screen (`surfaceMenu` over a
/// within-window blur, hairline, menu shadow, 18 inset).
private struct DropCardSurface: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Drop.radius, style: .continuous)
        content
            .padding(Theme.Drop.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                MenuSurface(shape: shape)
                    .shadow(
                        color: .black.opacity(Theme.Drop.shadowOpacity), radius: Theme.Drop.shadowRadius,
                        y: Theme.Drop.shadowY)
            )
            .overlay(Hairline(shape: shape, width: Theme.Drop.hairline))
    }
}

// MARK: - The drag card

/// Variant 1, Drop's header: "dev_android36 · splito-1.4.0.apk · 61 MB", the app's icon at 60,
/// "Splito 1.4.0" as the title, and the chip that says what letting go does.
struct DragCardView: View {
    let drag: DropModel.Drag
    /// The dragged apps' icons as read so far, in drag order.
    let icons: [NSImage]

    var body: some View {
        let card = drag.card
        VStack(alignment: .leading, spacing: Theme.Drop.sectionGap) {
            (Text(card.source).font(Theme.Typeface.dropHeaderStrong).foregroundStyle(Kit.Colour.bodyText)
                + Text(" · \(card.header)").font(Theme.Typeface.dropHeader).foregroundStyle(Kit.Colour.secondaryText))
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: Theme.Drop.mediaGap) {
                DropMedia(media: card.media, size: Theme.Drop.media, icon: icons.first, stackIcons: icons)
                VStack(alignment: .leading, spacing: Theme.Drop.chipGap) {
                    DropTitle(title: card.title, version: card.version)
                    HStack(spacing: Theme.Drop.statusGap) {
                        DropChip(text: card.chip, isWarning: card.tone == .warning)
                            .accessibilityIdentifier("drop-chip")
                        if drag.showsSpinner {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityLabel("Reading the app")
                        }
                    }
                }
            }
        }
        .modifier(DropCardSurface())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.announcement)
        .accessibilityIdentifier("drop-drag-card")
    }
}

/// "Splito 1.4.0": the name in the panel title's weight, the version regular and secondary.
private struct DropTitle: View {
    let title: String
    let version: String?

    var body: some View {
        let name = Text(title).font(Theme.Typeface.dropTitle).foregroundStyle(Kit.Colour.bodyText)
        let full =
            version.map {
                name + Text(" \($0)").font(Theme.Typeface.dropTitleVersion).foregroundStyle(Kit.Colour.secondaryText)
            } ?? name
        full
            .tracking(Theme.Typeface.dropTitleTracking)
            .lineLimit(1)
            .truncationMode(.middle)
    }
}

/// The kit's Chip: capsule, caption size, group-label weight. Neutral for New and Update, the
/// warning chip for an older build: colour carries risk only, and the words say it too.
struct DropChip: View {
    let text: String
    var isWarning = false

    var body: some View {
        Text(text)
            .font(Theme.Typeface.dropChip)
            .foregroundStyle(isWarning ? Kit.Colour.warnText : Kit.Colour.secondaryText)
            .lineLimit(1)
            .padding(.horizontal, Theme.Drop.chipPaddingH)
            .padding(.vertical, Theme.Drop.chipPaddingV)
            .background(Capsule().fill(isWarning ? Kit.Colour.warnFill : Kit.Colour.infoFill))
            .overlay(Hairline(shape: Capsule(), colour: isWarning ? Kit.Colour.warning : Kit.Colour.hairline))
            .fixedSize()
    }
}

/// The app's icon from the `.apk`, else the generic tile: an app, a photo, a file, a folder or
/// a refused drop. Several items overlap three small tiles.
struct DropMedia: View {
    let media: DragCard.Media
    let size: CGFloat
    let icon: NSImage?
    /// The apps' icons for a stack, first first; an app without one is a plain tile.
    var stackIcons: [NSImage] = []

    var body: some View {
        switch media {
        case .appIcon:
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * Theme.Drop.tileRatio, style: .continuous))
                    .accessibilityHidden(true)
            } else {
                DropTile(glyph: .app, size: size)
            }
        case .glyph(let glyph):
            DropTile(glyph: glyph, size: size)
        case .stack(let apps, let files):
            let tile = Theme.Drop.stackTile
            let step = (size - tile) / CGFloat(Theme.Drop.stackCount - 1)
            let count = min(Theme.Drop.stackCount, apps + files)
            let appTiles = min(apps, count - min(files, 1))
            ZStack(alignment: .topLeading) {
                ForEach(0..<count, id: \.self) { index in
                    let isTop = index == count - 1
                    let tileShape = RoundedRectangle(cornerRadius: tile * Theme.Drop.tileRatio, style: .continuous)
                    Group {
                        if index < appTiles, index < stackIcons.count {
                            Image(nsImage: stackIcons[index])
                                .resizable()
                                .interpolation(.high)
                                .frame(width: tile, height: tile)
                                .clipShape(tileShape)
                        } else {
                            // Only the top tile has room for its glyph; the ones under it are plain.
                            DropTile(glyph: index < appTiles ? .app : .file, size: tile, showsGlyph: isTop)
                        }
                    }
                    .background(tileShape.fill(Kit.Colour.menuSurfaceSolid).padding(-Theme.Drop.stackRing))
                    .offset(x: CGFloat(index) * step, y: CGFloat(index) * step)
                }
            }
            .frame(width: size, height: size, alignment: .topLeading)
            .accessibilityHidden(true)
        }
    }
}

/// The generic tile: `surfaceCard` with a hairline and a secondary glyph.
struct DropTile: View {
    let glyph: DragCard.Glyph
    let size: CGFloat
    var showsGlyph = true

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * Theme.Drop.tileRatio, style: .continuous)
        shape.fill(Kit.Colour.infoFill)
            .overlay(Hairline(shape: shape))
            .overlay {
                if showsGlyph {
                    Image(systemName: Self.symbol(glyph))
                        .font(.system(size: size >= Theme.Drop.media ? Theme.Drop.tileGlyph : Theme.Drop.listGlyph))
                        .foregroundStyle(Kit.Colour.secondaryText)
                }
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    static func symbol(_ glyph: DragCard.Glyph) -> String {
        switch glyph {
        case .app: "shippingbox"
        case .photo: "photo"
        case .file: "doc"
        case .folder: "folder"
        case .refused: "nosign"
        }
    }
}

// MARK: - The result card

/// After the drop (option A): one file shows the app or file with its own status and buttons;
/// several show a list, one row each. A downgrade asks first, with Cancel the default.
struct DropResultCard: View {
    let drop: DropModel
    let job: DropJob

    var body: some View {
        Group {
            if job.items.count == 1, let item = job.items.first {
                single(item)
            } else {
                list
            }
        }
        .modifier(DropCardSurface())
        .onHover { drop.isHovered = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Drop on \(drop.jobEmulator)")
        .accessibilityIdentifier("drop-card")
    }

    // MARK: One file

    private func single(_ item: DropJob.Item) -> some View {
        VStack(alignment: .leading, spacing: Theme.Drop.sectionGap) {
            DropItemHead(item: item, icon: drop.icons[item.file])
            status(item)
            if item.failure != nil, drop.showsDetails { details }
            actions(for: item)
        }
    }

    @ViewBuilder private func status(_ item: DropJob.Item) -> some View {
        switch item.state {
        case .waiting:
            HStack(spacing: Theme.Drop.statusGap) {
                ProgressView().controlSize(.small)
                Text("Reading the app's details…").font(Theme.Typeface.dropMeta)
                    .foregroundStyle(Kit.Colour.secondaryText)
            }
        case .sending(let sent, let total):
            progress(
                fraction: total.map { $0 > 0 ? Double(sent) / Double($0) * Theme.Drop.progressCeiling : 0 } ?? 0,
                label: item.isApp ? "Installing on \(drop.jobEmulator)" : "Copying to Downloads",
                detail: total.map { DropJob.progressText(sent: sent, total: $0) })
        case .installing:
            progress(fraction: Theme.Drop.progressCeiling, label: "Installing on \(drop.jobEmulator)", detail: nil)
        case .asking:
            DropWarning(text: DropModel.downgradeQuestion(item, emulator: drop.jobEmulator))
        case .installed:
            DropDone(text: "Installed on \(drop.jobEmulator)")
        case .copied:
            DropDone(
                text: item.kind == .file(isMedia: true)
                    ? "Copied to Downloads. Photos shows it too." : "Copied to Downloads.")
        case .failed(let failure):
            DropFailureRow(failure: failure)
        case .skipped:
            DropDone(text: "Not installed.")
        }
    }

    private func progress(fraction: Double, label: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: Theme.Drop.statusGap) {
            DropProgressBar(fraction: fraction, label: label)
            HStack {
                Text(label)
                Spacer(minLength: Theme.Drop.statusGap)
                if let detail { Text(detail).monospacedDigit() }
            }
            .font(Theme.Typeface.dropMeta)
            .foregroundStyle(Kit.Colour.secondaryText)
            .lineLimit(1)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder private func actions(for item: DropJob.Item) -> some View {
        switch item.state {
        case .asking:
            DropButtons {
                Spacer(minLength: 0)
                question
            }
        case .installed, .copied, .failed, .skipped:
            DropButtons {
                if item.failure?.code != nil { detailsLink }
                Spacer(minLength: 0)
                if let intent = DeviceIntent.after(item) {
                    Button("Close") { drop.dismiss() }
                        .buttonStyle(.nidusSecondary)
                        .accessibilityIdentifier("drop-close")
                    Button(intent == .showDownloads ? "Show" : "Open \(item.name)") { drop.perform(item) }
                        .buttonStyle(.nidusPrimary)
                        .accessibilityIdentifier(intent == .showDownloads ? "drop-show" : "drop-open")
                } else {
                    Button("Close") { drop.dismiss() }
                        .buttonStyle(.nidusSecondary)
                        .accessibilityIdentifier("drop-close")
                }
            }
        default:
            EmptyView()
        }
    }

    /// Install older version as the secondary, Cancel as the moss primary and the default
    /// (Return), as every destructive confirmation in Pane.
    @ViewBuilder private var question: some View {
        Button("Install older version") { drop.answerDowngrade(install: true) }
            .buttonStyle(.nidusSecondary)
            .accessibilityIdentifier("drop-install-older")
        Button("Cancel") { drop.answerDowngrade(install: false) }
            .buttonStyle(.nidusPrimary)
            .accessibilityIdentifier("drop-cancel")
    }

    private var detailsLink: some View {
        Button(drop.showsDetails ? "Hide details" : "Details") { drop.toggleDetails() }
            .buttonStyle(.nidusLink())
            .accessibilityHint("Shows the reason adb gave.")
            .accessibilityIdentifier("drop-details")
    }

    private var details: some View {
        DropDetails(text: drop.detailsText)
    }

    // MARK: Several files

    private var list: some View {
        VStack(alignment: .leading, spacing: Theme.Drop.listHeadGap) {
            Text(job.title)
                .font(Theme.Typeface.dropRowTitle)
                .foregroundStyle(Kit.Colour.bodyText)
                .accessibilityAddTraits(.isHeader)
            ViewThatFits(in: .vertical) {
                rows
                ScrollView { rows }
            }
            if let asking = job.asking {
                DropWarning(text: DropModel.downgradeQuestion(asking, emulator: drop.jobEmulator))
                DropButtons {
                    Spacer(minLength: 0)
                    question
                }
            } else if !job.isFinished {
                DropProgressBar(fraction: job.fraction(ceiling: Theme.Drop.progressCeiling), label: job.title)
            } else {
                if drop.showsDetails { details }
                DropButtons {
                    if job.failures.contains(where: { $0.failure?.code != nil }) { detailsLink }
                    Spacer(minLength: 0)
                    Button("Close") { drop.dismiss() }
                        .buttonStyle(.nidusSecondary)
                        .accessibilityIdentifier("drop-close")
                }
            }
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: Theme.Drop.listRowGap) {
            ForEach(job.items) { item in
                DropListRow(item: item, icon: drop.icons[item.file]) { drop.perform(item) }
            }
        }
    }
}

/// The app (icon, name, "1.4.0 · dev.niduslabs.splito", the version chip) or the file (tile,
/// name, "2.4 MB · Photo") at the top of a one-file card.
private struct DropItemHead: View {
    let item: DropJob.Item
    let icon: NSImage?

    var body: some View {
        HStack(spacing: Theme.Drop.mediaGap) {
            DropMedia(media: DropListRow.media(item), size: Theme.Drop.media, icon: icon)
            VStack(alignment: .leading, spacing: Theme.Drop.metaGap) {
                Text(item.name)
                    .font(Theme.Typeface.dropTitle)
                    .tracking(Theme.Typeface.dropTitleTracking)
                    .foregroundStyle(Kit.Colour.bodyText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(meta)
                    .font(Theme.Typeface.dropMeta)
                    .foregroundStyle(Kit.Colour.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let chip = DropListRow.chip(item) {
                    DropChip(text: chip.text, isWarning: chip.isWarning)
                        .padding(.top, Theme.Drop.chipGap)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var meta: String {
        if let badging = item.badging {
            let version = badging.versionName.isEmpty ? String(badging.versionCode) : badging.versionName
            return "\(version) · \(badging.packageName)"
        }
        let size = item.size.map(DragCard.sizeText)
        let kind =
            switch item.kind {
            case .app: "App"
            case .file(isMedia: true): "Photo or video"
            case .file: "File"
            }
        return [size, kind].compactMap { $0 }.joined(separator: " · ")
    }
}

/// One file in a several-file card: its icon at 32, the name and version over the version chip
/// or why it failed, and its state, with Open or Show once done.
private struct DropListRow: View {
    let item: DropJob.Item
    let icon: NSImage?
    let perform: () -> Void

    var body: some View {
        HStack(spacing: Theme.Drop.listIconGap) {
            DropMedia(media: Self.media(item), size: Theme.Drop.listIcon, icon: icon)
            VStack(alignment: .leading, spacing: Theme.Drop.metaGap) {
                title
                if let failure = item.failure {
                    Text(failure.rowReason)
                        .font(Theme.Typeface.dropMeta)
                        .foregroundStyle(Kit.Colour.error)
                        .lineLimit(2)
                } else if let chip = Self.chip(item) {
                    DropChip(text: chip.text, isWarning: chip.isWarning)
                }
            }
            Spacer(minLength: Theme.Drop.statusGap)
            state
            if let intent = DeviceIntent.after(item) {
                Button(intent == .showDownloads ? "Show" : "Open", action: perform)
                    .buttonStyle(.nidusSmall)
                    .accessibilityLabel(intent == .showDownloads ? "Show in Downloads" : "Open \(item.name)")
            }
        }
        .frame(minHeight: Theme.Drop.listRowHeight)
        .accessibilityElement(children: .combine)
    }

    private var title: some View {
        let name = Text(item.name).font(Theme.Typeface.dropRow).foregroundStyle(Kit.Colour.bodyText)
        let version = item.badging.map { $0.versionName }.flatMap { $0.isEmpty ? nil : $0 }
        return
            (version.map {
                name + Text(" \($0)").font(Theme.Typeface.dropRow).foregroundStyle(Kit.Colour.secondaryText)
            }
            ?? name)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    @ViewBuilder private var state: some View {
        HStack(spacing: Theme.Drop.listRowGap) {
            switch item.state {
            case .waiting, .asking:
                Text("Waiting").foregroundStyle(Kit.Colour.secondaryText)
            case .sending, .installing:
                ProgressView().controlSize(.small)
                Text(item.isApp ? "Installing" : "Copying").foregroundStyle(Kit.Colour.secondaryText)
            // Next to Open or Show the tick says it alone, so the name keeps the room.
            case .installed:
                Image(systemName: "checkmark.circle").foregroundStyle(Kit.Colour.good)
                    .accessibilityLabel("Installed")
                if DeviceIntent.after(item) == nil { Text("Installed").foregroundStyle(Kit.Colour.secondaryText) }
            case .copied:
                Image(systemName: "checkmark.circle").foregroundStyle(Kit.Colour.good)
                    .accessibilityLabel("Copied")
            case .skipped:
                Text("Not installed").foregroundStyle(Kit.Colour.secondaryText)
            case .failed:
                Image(systemName: "exclamationmark.circle").foregroundStyle(Kit.Colour.error)
                Text("Failed").foregroundStyle(Kit.Colour.error)
            }
        }
        .font(Theme.Typeface.dropMeta)
        .lineLimit(1)
        .fixedSize()
    }

    static func media(_ item: DropJob.Item) -> DragCard.Media {
        switch item.kind {
        case .app:
            guard let badging = item.badging, badging.hasDrawableIcon, let path = badging.iconPath else {
                return .glyph(.app)
            }
            return .appIcon(apk: item.file, path: path)
        case .file(let isMedia): return .glyph(isMedia ? .photo : .file)
        }
    }

    /// The version chip after the drop: what installing did or will do to the device's copy.
    static func chip(_ item: DropJob.Item) -> (text: String, isWarning: Bool)? {
        switch item.change {
        case .new: ("New", false)
        case .update(let from): ("Update from \(from)", false)
        case .reinstall: ("Reinstall", false)
        case .older(let than): ("Older than \(than)", true)
        case nil: nil
        }
    }
}

/// The moss bar on its track, held under the ceiling until the work is done (`progressHold`).
private struct DropProgressBar: View {
    let fraction: Double
    let label: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let clamped = min(max(fraction, 0), 1)
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Kit.Colour.track)
                Capsule().fill(Kit.Colour.accent).frame(width: geometry.size.width * clamped)
            }
        }
        .frame(height: Theme.Drop.progressHeight)
        .animation(reduceMotion ? nil : Kit.Motion.progress, value: clamped)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue("\(Int((clamped * 100).rounded())) percent")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// A green tick and what happened ("Installed on dev_android36").
private struct DropDone: View {
    let text: String

    var body: some View {
        HStack(spacing: Theme.Drop.rowGap) {
            Image(systemName: "checkmark.circle").font(.system(size: Theme.Drop.rowIcon))
                .foregroundStyle(Kit.Colour.good)
                .accessibilityHidden(true)
            Text(text).font(Theme.Typeface.dropMeta).foregroundStyle(Kit.Colour.bodyText)
        }
    }
}

/// A red mark, the title ("Couldn't install Splito.") and the plain reason under it.
private struct DropFailureRow: View {
    let failure: DropFailure

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Drop.failureGap) {
            Image(systemName: "exclamationmark.circle").font(.system(size: Theme.Drop.rowIcon))
                .foregroundStyle(Kit.Colour.error)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Drop.metaGap) {
                Text(failure.title).font(Theme.Typeface.dropRowTitle).foregroundStyle(Kit.Colour.bodyText)
                if let body = failure.body {
                    Text(body).font(Theme.Typeface.dropMeta).foregroundStyle(Kit.Colour.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The downgrade question's warning box.
private struct DropWarning: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Drop.boxGap) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: Theme.Drop.rowIcon))
                .foregroundStyle(Kit.Colour.warning)
                .accessibilityHidden(true)
            Text(text).font(Theme.Typeface.dropMeta).foregroundStyle(Kit.Colour.warnText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.Drop.boxPaddingH)
        .padding(.vertical, Theme.Drop.boxPaddingV)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Drop.boxRadius, style: .continuous).fill(Kit.Colour.warnFill)
        )
        .accessibilityElement(children: .combine)
    }
}

/// adb's own line, in mono, with Copy.
private struct DropDetails: View {
    let text: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Drop.boxRadius, style: .continuous)
        VStack(alignment: .leading, spacing: Theme.Drop.statusGap) {
            Text(text)
                .font(Theme.Typeface.dropDetails)
                .foregroundStyle(Kit.Colour.secondaryText)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Button("Copy") {
                PaneModel.pasteboard.clearContents()
                PaneModel.pasteboard.setString(text, forType: .string)
            }
            .buttonStyle(.nidusLink())
            .accessibilityHint("Copies adb's reason.")
        }
        .padding(.horizontal, Theme.Drop.boxPaddingH)
        .padding(.vertical, Theme.Drop.detailsPaddingV)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(Kit.Colour.infoFill))
        .overlay(Hairline(shape: shape))
        .accessibilityIdentifier("drop-details-box")
    }
}

/// The card's button row: a link on the left, buttons on the right.
private struct DropButtons<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: Theme.Drop.buttonGap) { content }
    }
}
