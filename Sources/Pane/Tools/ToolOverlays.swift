import PaneCore
import SwiftUI

/// What the tool that is on draws over the live screen (boards 9 to 11). Never takes clicks:
/// the screen view under it hands them to `ToolsModel`.
struct ToolOverlay: View {
    let tools: ToolsModel

    var body: some View {
        ZStack {
            switch tools.active {
            case .inspect: InspectOverlay(tools: tools)
            case .measure: MeasureOverlay(tools: tools)
            case .pickColour: ColourOverlay(tools: tools)
            case nil: EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

/// A chip (`tool.chip`): ink with paper text in both modes, for a size, a distance, a length
/// or a hex. Digits are a fixed width so it doesn't jitter.
struct ToolChip<Leading: View>: View {
    let text: String
    @ViewBuilder var leading: Leading

    var body: some View {
        HStack(spacing: Theme.Tools.chipGap) {
            leading
            Text(text)
                .font(Theme.Typeface.toolChip)
                .foregroundStyle(Color(nsColor: Theme.Palette.toolChipText))
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, Theme.Tools.chipPaddingH)
        .frame(height: Theme.Tools.chipHeight)
        .background(
            RoundedRectangle(cornerRadius: Theme.Tools.chipRadius, style: .continuous)
                .fill(Color(nsColor: Theme.Palette.toolChip))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Tools.chipRadius, style: .continuous)
                .strokeBorder(Color(nsColor: Theme.Palette.toolChipRing), lineWidth: Theme.Tools.chipRing)
        )
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

extension ToolChip where Leading == EmptyView {
    init(text: String) {
        self.init(text: text) { EmptyView() }
    }
}

/// A straight line in a tool colour with the paper halo on each side. Guides are dashed.
struct ToolLine: View {
    let from: CGPoint
    let to: CGPoint
    let colour: NSColor
    var dashed = false

    var body: some View {
        let path = Path { path in
            path.move(to: from)
            path.addLine(to: to)
        }
        ZStack {
            path.stroke(
                Color(nsColor: Theme.Palette.toolHalo),
                lineWidth: Theme.Tools.outlineWidth + 2 * Theme.Tools.haloWidth)
            path.stroke(
                Color(nsColor: colour),
                style: StrokeStyle(lineWidth: Theme.Tools.outlineWidth, dash: dashed ? Theme.Tools.guideDash : []))
        }
    }
}

/// Inspect layout: the view under the pointer outlined with its size in a chip. A click pins
/// it: amber dashed guides show the distance to its parent's edges, and a card lists its type,
/// frame, pixel size and id. The card and the distance chips are placed so none covers
/// another, the outline or the size chip (`LabelPlacement`); a distance chip stays on its guide.
struct InspectOverlay: View {
    let tools: ToolsModel

    var body: some View {
        GeometryReader { proxy in
            if let view = tools.pinned ?? tools.hovered, let scale = tools.scale {
                let rect = scale.view(view.node.frame)
                let sizeText = sizeText(view.node.frame.size)
                let sizeChip = CGRect(
                    origin: CGPoint(x: chipLeading(for: rect, in: proxy.size), y: chipTop(for: rect)),
                    size: ToolChipMetrics.size(of: sizeText))
                let pinned = tools.pinned.map {
                    layout(pinned: $0, rect: rect, sizeChip: sizeChip, scale: scale, in: proxy.size)
                }
                ZStack(alignment: .topLeading) {
                    if let pinned {
                        ForEach(pinned.guides.indices, id: \.self) { index in
                            let guide = pinned.guides[index]
                            ToolLine(from: guide.from, to: guide.to, colour: Theme.Palette.toolGuide, dashed: true)
                        }
                    }
                    outline(rect)
                    ToolChip(text: sizeText)
                        .alignmentGuide(.leading) { _ in -sizeChip.minX }
                        .alignmentGuide(.top) { _ in -sizeChip.minY }
                    if let pinned {
                        ForEach(pinned.guides.indices, id: \.self) { index in
                            let guide = pinned.guides[index]
                            if let text = guide.text, let chip = guide.chip {
                                ToolChip(text: text).position(x: chip.midX, y: chip.midY)
                            }
                        }
                        InspectCard(node: view.node, density: tools.density)
                            .frame(width: pinned.card.width)
                            .position(x: pinned.card.midX, y: pinned.card.midY)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }
        }
    }

    private struct Guide {
        let from: CGPoint
        let to: CGPoint
        /// Nil when the chip fits nowhere on its guide: the guide shows without its number.
        let text: String?
        let chip: CGRect?
    }

    private struct PinnedLayout {
        let guides: [Guide]
        let card: CGRect
    }

    /// Each distance chip on its guide first (they belong to the geometry; a chip slides only
    /// along its guide, and is hidden when it fits nowhere there), then the card where it is
    /// clear of them: under the outline, else above it, else at the screen's bottom or top.
    private func layout(
        pinned view: InspectedView, rect: CGRect, sizeChip: CGRect, scale: ScreenScale, in size: CGSize
    ) -> PinnedLayout {
        let margin = Theme.Tools.cardMargin
        var placement = LabelPlacement(
            bounds: CGRect(origin: .zero, size: size).insetBy(dx: margin, dy: margin), spacing: Theme.Tools.chipGap,
            avoiding: [rect.insetBy(dx: -Theme.Tools.haloWidth, dy: -Theme.Tools.haloWidth), sizeChip])
        let frame = view.node.frame
        let parent = view.parentFrame ?? CGRect(origin: .zero, size: scale.pixelSize)
        let inside = EdgeDistances(frame: frame, parent: parent)
        let outer = scale.view(parent)
        // A side the view touches gets no guide.
        let sides: [(CGFloat, CGPoint, CGPoint)] = [
            (inside.left, CGPoint(x: outer.minX, y: rect.midY), CGPoint(x: rect.minX, y: rect.midY)),
            (inside.right, CGPoint(x: rect.maxX, y: rect.midY), CGPoint(x: outer.maxX, y: rect.midY)),
            (inside.top, CGPoint(x: rect.midX, y: outer.minY), CGPoint(x: rect.midX, y: rect.minY)),
            (inside.bottom, CGPoint(x: rect.midX, y: rect.maxY), CGPoint(x: rect.midX, y: outer.maxY)),
        ]
        let guides = sides.filter { $0.0 > 0 }.map { length, from, to in
            // In dp the number is already short; "123 px" can drop its unit.
            let texts =
                tools.density.map { ["\($0.wholeDp(length))"] }
                ?? ["\(Int(length.rounded())) px", "\(Int(length.rounded()))"]
            let placed = placement.placeOnGuide(
                from: from, to: to, sizes: texts.map(ToolChipMetrics.size(of:)), gap: Theme.Tools.chipGap)
            return Guide(from: from, to: to, text: placed.map { texts[$0.size] }, chip: placed?.frame)
        }
        let rows = CGFloat(InspectCard.rowCount(for: view.node))
        let cardSize = CGSize(
            width: min(Theme.Tools.cardWidth, size.width - 2 * margin),
            height: rows * Theme.Tools.cardLineHeight + (rows - 1) * Theme.Tools.cardRowGap
                + 2 * Theme.Tools.cardPaddingV)
        let below = rect.maxY + Theme.Tools.cardGap + cardSize.height / 2
        let above = min(rect.minY, sizeChip.minY) - Theme.Tools.cardGap - cardSize.height / 2
        let card = placement.place(
            size: cardSize,
            candidates: [
                CGPoint(x: rect.midX, y: below), CGPoint(x: rect.midX, y: above),
                CGPoint(x: size.width / 2, y: size.height - margin - cardSize.height / 2),
                CGPoint(x: size.width / 2, y: margin + cardSize.height / 2),
            ])
        return PinnedLayout(guides: guides, card: card)
    }

    private func sizeText(_ size: CGSize) -> String {
        tools.density?.sizeText(size) ?? DensityScale.pixelText(size)
    }

    /// Moss with a paper halo outside and inside, over a moss wash.
    private func outline(_ rect: CGRect) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Tools.outlineRadius, style: .continuous)
        let width = max(rect.width, 2 * Theme.Tools.outlineWidth)
        let height = max(rect.height, 2 * Theme.Tools.outlineWidth)
        return shape.fill(Color(nsColor: Theme.Palette.toolFill))
            .overlay(
                shape.inset(by: -Theme.Tools.haloWidth)
                    .strokeBorder(Color(nsColor: Theme.Palette.toolHalo), lineWidth: Theme.Tools.haloWidth)
            )
            .overlay(
                shape.inset(by: Theme.Tools.outlineWidth)
                    .strokeBorder(Color(nsColor: Theme.Palette.toolHalo), lineWidth: Theme.Tools.haloWidth)
            )
            .overlay(shape.strokeBorder(Color(nsColor: Theme.Palette.toolSelect), lineWidth: Theme.Tools.outlineWidth))
            .frame(width: width, height: height)
            .offset(x: rect.minX, y: rect.minY)
    }

    /// The chip sits above the outline's left end, or inside its top when there's no room.
    private func chipTop(for rect: CGRect) -> CGFloat {
        let above = rect.minY - Theme.Tools.chipHeight - Theme.Tools.chipGap
        return above >= 0 ? above : rect.minY + Theme.Tools.chipGap
    }

    private func chipLeading(for rect: CGRect, in size: CGSize) -> CGFloat {
        min(max(rect.minX, 0), max(0, size.width - Theme.Tools.cardWidth / 2))
    }
}

/// A chip's size for its text, for placing it before it is drawn.
enum ToolChipMetrics {
    @MainActor
    static func size(of text: String) -> CGSize {
        let width = (text as NSString).size(withAttributes: [.font: Theme.Tools.chipFont]).width
        return CGSize(width: ceil(width) + 2 * Theme.Tools.chipPaddingH, height: Theme.Tools.chipHeight)
    }
}

/// The pinned view's details: its label when it has one, its type, its frame in dp, its size
/// in pixels and its resource id.
struct InspectCard: View {
    let node: LayoutNode
    let density: DensityScale?

    /// How many rows the card shows for a view, for placing it.
    static func rowCount(for node: LayoutNode) -> Int {
        3 + (node.label == nil ? 0 : 1) + (node.resourceID.isEmpty ? 0 : 1)
    }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: Theme.Tools.cardColumnGap, verticalSpacing: Theme.Tools.cardRowGap)
        {
            if let label = node.label { row("Label", label) }
            row("Type", node.shortClassName)
            row("Frame", density?.frameText(node.frame) ?? "x \(Int(node.frame.minX)), y \(Int(node.frame.minY)) px")
            row("Pixels", DensityScale.pixelText(node.frame.size))
            if !node.resourceID.isEmpty { row("Id", node.resourceID) }
        }
        .padding(.horizontal, Theme.Tools.cardPaddingH)
        .padding(.vertical, Theme.Tools.cardPaddingV)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            MenuSurface(
                shape: RoundedRectangle(cornerRadius: Theme.Tools.cardRadius, style: .continuous),
                fill: Theme.Palette.toolChip, solidFill: Theme.Palette.toolChipSolid, blursInLight: true
            )
            .shadow(
                color: .black.opacity(Theme.Tools.cardShadowOpacity), radius: Theme.Tools.cardShadowRadius,
                y: Theme.Tools.cardShadowY)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Tools.cardRadius, style: .continuous)
                .strokeBorder(Color(nsColor: Theme.Palette.toolChipRing), lineWidth: Theme.Tools.chipRing)
        )
        .accessibilityElement(children: .combine)
    }

    private func row(_ key: String, _ value: String) -> some View {
        GridRow {
            Text(key)
                .font(Theme.Typeface.toolCard)
                .foregroundStyle(Color(nsColor: Theme.Palette.toolChipSecondary))
                .frame(width: Theme.Tools.cardKeyWidth, alignment: .leading)
            Text(value)
                .font(Theme.Typeface.toolCard)
                .foregroundStyle(Color(nsColor: Theme.Palette.toolChipText))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

/// Measure: the dragged line in moss with end caps, its length in a chip, and an amber dashed
/// guide along any view edge its end snapped to.
struct MeasureOverlay: View {
    let tools: ToolsModel

    var body: some View {
        GeometryReader { proxy in
            if let line = tools.measurement, let scale = tools.scale {
                let start = scale.view(line.start)
                let end = scale.view(line.end)
                ZStack(alignment: .topLeading) {
                    if let x = tools.snappedX {
                        let viewX = scale.view(CGPoint(x: x, y: 0)).x
                        ToolLine(
                            from: CGPoint(x: viewX, y: 0), to: CGPoint(x: viewX, y: proxy.size.height),
                            colour: Theme.Palette.toolGuide, dashed: true)
                    }
                    if let y = tools.snappedY {
                        let viewY = scale.view(CGPoint(x: 0, y: y)).y
                        ToolLine(
                            from: CGPoint(x: 0, y: viewY), to: CGPoint(x: proxy.size.width, y: viewY),
                            colour: Theme.Palette.toolGuide, dashed: true)
                    }
                    ToolLine(from: start, to: end, colour: Theme.Palette.toolSelect)
                    if line.lengthPixels > 0 {
                        cap(at: start, along: start, end)
                        cap(at: end, along: start, end)
                        ToolChip(text: tools.density.map { line.text(scale: $0) } ?? line.pixelText)
                            .position(chipCentre(start: start, end: end, in: proxy.size))
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }
        }
    }

    /// A short stroke across the line's end.
    private func cap(at point: CGPoint, along start: CGPoint, _ end: CGPoint) -> some View {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(hypot(dx, dy), .leastNonzeroMagnitude)
        let half = Theme.Tools.capLength / 2
        let normal = CGVector(dx: -dy / length * half, dy: dx / length * half)
        return ToolLine(
            from: CGPoint(x: point.x - normal.dx, y: point.y - normal.dy),
            to: CGPoint(x: point.x + normal.dx, y: point.y + normal.dy), colour: Theme.Palette.toolSelect)
    }

    /// Above a level line's middle, beside an upright one's.
    private func chipCentre(start: CGPoint, end: CGPoint, in size: CGSize) -> CGPoint {
        let middle = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let lift = Theme.Tools.chipHeight / 2 + Theme.Tools.capLength / 2 + Theme.Tools.chipGap
        let level = abs(end.x - start.x) >= abs(end.y - start.y)
        // Wide enough for "999 dp · 9999 px" beside an upright line.
        let side = Theme.Tools.cardWidth / 4 + Theme.Tools.capLength
        let point =
            level
            ? CGPoint(x: middle.x, y: middle.y - lift < Theme.Tools.chipHeight ? middle.y + lift : middle.y - lift)
            : CGPoint(x: middle.x + side > size.width - side / 2 ? middle.x - side : middle.x + side, y: middle.y)
        return CGPoint(x: min(max(point.x, 0), size.width), y: min(max(point.y, 0), size.height))
    }
}

/// Pick colour: a round loupe of the pixels around the pointer, the chosen one outlined in
/// moss, and a chip beside it with the colour and its hex.
struct ColourOverlay: View {
    let tools: ToolsModel

    var body: some View {
        GeometryReader { proxy in
            if let point = tools.hoverPoint, let colour = tools.colour, !tools.loupe.isEmpty {
                let side = CGFloat(tools.loupe.count) * Theme.Tools.loupeCell
                let centre = loupeCentre(for: point, side: side, in: proxy.size)
                let chipOnLeft = centre.x + side / 2 + Theme.Tools.cardWidth / 2 > proxy.size.width
                ZStack(alignment: .topLeading) {
                    Loupe(cells: tools.loupe)
                        .frame(width: side, height: side)
                        .position(centre)
                    ToolChip(text: tools.copied.map { "Copied \($0)" } ?? colour.hex) {
                        RoundedRectangle(cornerRadius: Theme.Tools.swatchRadius, style: .continuous)
                            .fill(Color(colour))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Tools.swatchRadius, style: .continuous)
                                    .strokeBorder(
                                        Color(nsColor: Theme.Palette.toolChipRing), lineWidth: Theme.Tools.chipRing)
                            )
                            .frame(width: Theme.Tools.swatchSize, height: Theme.Tools.swatchSize)
                    }
                    .alignmentGuide(.leading) { dimensions in
                        chipOnLeft
                            ? -(centre.x - side / 2 - Theme.Tools.loupeChipGap - dimensions.width)
                            : -(centre.x + side / 2 + Theme.Tools.loupeChipGap)
                    }
                    .alignmentGuide(.top) { _ in -(centre.y - Theme.Tools.chipHeight / 2) }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }
        }
    }

    /// Below and to the right of the pointer, flipped to the other side near an edge.
    private func loupeCentre(for point: CGPoint, side: CGFloat, in size: CGSize) -> CGPoint {
        let reach = Theme.Tools.loupeOffset + side / 2
        return CGPoint(
            x: point.x + reach + side / 2 <= size.width ? point.x + reach : point.x - reach,
            y: point.y + reach + side / 2 <= size.height ? point.y + reach : point.y - reach)
    }
}

/// The loupe: a grid of pixels in a circle, a paper ring inside an ink ring so its edge shows
/// on light and dark apps alike, and the middle pixel outlined in moss.
private struct Loupe: View {
    let cells: [[PickedColour]]

    var body: some View {
        Canvas { context, size in
            let count = CGFloat(cells.count)
            guard count > 0 else { return }
            let cell = size.width / count
            for (row, colours) in cells.enumerated() {
                for (column, colour) in colours.enumerated() {
                    // A hair of overlap keeps seams from showing between cells.
                    let rect = CGRect(
                        x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell + Theme.Tools.chipRing,
                        height: cell + Theme.Tools.chipRing)
                    context.fill(Path(rect), with: .color(Color(colour)))
                }
            }
            let middle = CGFloat(cells.count / 2) * cell
            let chosen = CGRect(x: middle, y: middle, width: cell, height: cell)
            context.stroke(
                Path(chosen.insetBy(dx: -Theme.Tools.haloWidth, dy: -Theme.Tools.haloWidth)),
                with: .color(Color(nsColor: Theme.Palette.toolHalo)), lineWidth: Theme.Tools.haloWidth)
            context.stroke(
                Path(chosen.insetBy(dx: Theme.Tools.outlineWidth / 2, dy: Theme.Tools.outlineWidth / 2)),
                with: .color(Color(nsColor: Theme.Palette.toolSelect)), lineWidth: Theme.Tools.outlineWidth)
        }
        .clipShape(Circle())
        .overlay(
            Circle().inset(by: -Theme.Tools.loupePaperRing)
                .strokeBorder(Color(nsColor: Theme.Palette.toolChipText), lineWidth: Theme.Tools.loupePaperRing)
        )
        .overlay(
            Circle().inset(by: -Theme.Tools.loupePaperRing - Theme.Tools.loupeInkRing)
                .strokeBorder(Color(nsColor: Theme.Palette.toolChip), lineWidth: Theme.Tools.loupeInkRing)
        )
        .shadow(
            color: .black.opacity(Theme.Tools.loupeShadowOpacity), radius: Theme.Tools.cardShadowRadius,
            y: Theme.Tools.cardShadowY
        )
        .accessibilityHidden(true)
    }
}

extension Color {
    init(_ colour: PickedColour) {
        let channelMax = 255.0
        self.init(
            .sRGB, red: Double(colour.red) / channelMax, green: Double(colour.green) / channelMax,
            blue: Double(colour.blue) / channelMax)
    }
}

/// The pill that takes the toolbar's place while a tool is on: the tool's glyph (a spinner
/// while it loads), its name or state, and Done or Try Again.
struct ToolModePill: View {
    let tools: ToolsModel
    let tool: PaneTool
    let state: ToolPillState

    var body: some View {
        HStack(spacing: Theme.ModePill.gap) {
            if state.isBusy {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: Theme.ModePill.iconSize, height: Theme.ModePill.iconSize)
            } else {
                Image(systemName: tool.symbolName)
                    .font(.system(size: Theme.ModePill.iconSize, weight: .regular))
                    .foregroundStyle(Color(nsColor: Theme.Palette.icon))
                    .frame(width: Theme.ModePill.iconSize, height: Theme.ModePill.iconSize)
                    .accessibilityHidden(true)
            }
            Text(state.text)
                .font(Theme.Typeface.modePill)
                .foregroundStyle(Color(nsColor: Theme.Palette.text))
                .lineLimit(1)
                .fixedSize()
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.updatesFrequently)
            Button(state.action.title) { tools.runPillAction() }
                .buttonStyle(ModePillButtonStyle())
        }
        .padding(.leading, Theme.ModePill.paddingLeading)
        .padding(.trailing, Theme.ModePill.paddingTrailing)
        .frame(minWidth: Theme.ModePill.minWidth)
        .frame(height: Theme.ModePill.height)
        .fixedSize()
        .background(
            Capsule().fill(Color(nsColor: Theme.Palette.modePill))
                .shadow(
                    color: .black.opacity(Theme.ModePill.shadowOpacity), radius: Theme.ModePill.shadowRadius,
                    y: Theme.ModePill.shadowY)
        )
        .overlay(
            Hairline(shape: Capsule(), width: Theme.ModePill.hairline, colour: Color(nsColor: Theme.Palette.hairline))
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tool.title)
    }
}

struct ModePillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typeface.modePillButton)
            .foregroundStyle(Color(nsColor: Theme.Palette.text))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, Theme.ModePill.buttonPaddingH)
            .frame(height: Theme.ModePill.buttonHeight)
            .background(Capsule().fill(Color(nsColor: Theme.Palette.modePillButton)))
            .overlay(
                Capsule().strokeBorder(Color(nsColor: Theme.Palette.hairline), lineWidth: Theme.ModePill.buttonHairline)
            )
            .overlay(
                Capsule().fill(
                    Color(nsColor: Theme.Palette.shade).opacity(
                        configuration.isPressed ? Theme.Toolbar.pressedOpacity : 0))
            )
            .contentShape(Capsule())
    }
}

/// The short line over the bottom of the screen: "Copied.", "Exporting GIF…", an error.
struct NoticePill: View {
    let model: PaneModel

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            if let notice = model.notice {
                HStack(spacing: Theme.Notice.gap) {
                    if model.noticeIsBusy {
                        ProgressView()
                            .controlSize(.small)
                            .colorScheme(.dark)
                    }
                    Text(notice)
                        .font(Theme.Typeface.notice)
                        .foregroundStyle(Color(nsColor: Theme.Palette.toolText))
                        .lineLimit(1)
                }
                .padding(.horizontal, Theme.Notice.paddingH)
                .frame(height: Theme.Notice.height)
                .background(Capsule().fill(Color(nsColor: Theme.Palette.toolSurface)))
                .overlay(
                    Capsule().strokeBorder(Color(nsColor: Theme.Palette.toolHairline), lineWidth: Theme.Notice.hairline)
                )
                .shadow(
                    color: .black.opacity(Theme.Notice.shadowOpacity), radius: Theme.Notice.shadowRadius,
                    y: Theme.Notice.shadowY
                )
                .padding(.bottom, Theme.Notice.bottomInset)
                .transition(.opacity)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: Theme.Notice.fadeDuration), value: model.notice)
        .allowsHitTesting(false)
    }
}
