import PaneCore
import SwiftUI

/// What the tool that is on draws over the live screen. Never takes clicks: the screen view
/// under it hands them to `ToolsModel`.
struct ToolOverlay: View {
    let tools: ToolsModel

    var body: some View {
        ZStack(alignment: .top) {
            switch tools.active {
            case .inspect: InspectOverlay(tools: tools)
            case .measure: MeasureOverlay(tools: tools)
            case .pickColour: ColourOverlay(tools: tools)
            case nil: EmptyView()
            }
            if let hint {
                ToolHint(text: hint)
                    .padding(.top, Theme.Tools.hintTop)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private var hint: String? {
        guard let tool = tools.active else { return nil }
        if tool == .inspect {
            if let problem = tools.layoutProblem { return problem }
            if tools.tree == nil { return "Reading layout…" }
        }
        return tool.hint
    }
}

/// The line at the top of the screen that names the tool and how to leave it.
struct ToolHint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.Typeface.toolHint)
            .foregroundStyle(Color(nsColor: Theme.Palette.toolText))
            .lineLimit(1)
            .padding(.horizontal, Theme.Tools.hintPaddingH)
            .frame(height: Theme.Tools.hintHeight)
            .toolSurface(in: Capsule())
            .accessibilityLabel(text)
    }
}

/// A small filled label: a size on an outline, a distance on a guide, a length on a line.
struct ToolTag: View {
    let text: String
    let colour: NSColor

    var body: some View {
        Text(text)
            .font(Theme.Typeface.toolTag)
            .foregroundStyle(Color(nsColor: Theme.Palette.toolTagText))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, Theme.Tools.tagPaddingH)
            .frame(height: Theme.Tools.tagHeight)
            .background(
                RoundedRectangle(cornerRadius: Theme.Tools.tagRadius, style: .continuous).fill(Color(nsColor: colour)))
    }
}

extension View {
    /// The dark surface the tools' cards and readouts sit on, readable over any app.
    func toolSurface(in shape: some InsettableShape) -> some View {
        background(shape.fill(Color(nsColor: Theme.Palette.toolSurface)))
            .overlay(
                shape.strokeBorder(Color(nsColor: Theme.Palette.toolHairline), lineWidth: Theme.Tools.hairline)
            )
            .shadow(
                color: .black.opacity(Theme.Tools.shadowOpacity), radius: Theme.Tools.shadowRadius,
                y: Theme.Tools.shadowY)
    }
}

/// Inspect Layout: the view under the pointer (or the pinned one) outlined, with its size in
/// dp, its distance to the nearest screen edges, and a card of details.
struct InspectOverlay: View {
    let tools: ToolsModel

    var body: some View {
        GeometryReader { proxy in
            if let node = tools.inspected, let scale = tools.scale {
                let rect = scale.view(node.frame)
                let isPinned = tools.pinned != nil
                let colour = isPinned ? Theme.Palette.toolPinned : Theme.Palette.toolOutline
                let density = tools.density
                let edges = EdgeDistances(frame: node.frame, screen: scale.pixelSize)
                ZStack(alignment: .topLeading) {
                    EdgeGuides(rect: rect, size: proxy.size, edges: edges, density: density)
                    Rectangle()
                        .fill(Color(nsColor: Theme.Palette.toolFill))
                        .overlay(Rectangle().strokeBorder(Color(nsColor: colour), lineWidth: Theme.Tools.outlineWidth))
                        .frame(
                            width: max(rect.width, Theme.Tools.outlineWidth),
                            height: max(rect.height, Theme.Tools.outlineWidth)
                        )
                        .offset(x: rect.minX, y: rect.minY)
                    ToolTag(text: density.sizeText(node.frame.size), colour: colour)
                        .position(sizeTagCentre(for: rect, in: proxy.size))
                    InspectCard(node: node, density: density, isPinned: isPinned)
                        .frame(width: min(Theme.Tools.cardWidth, proxy.size.width - 2 * Theme.Tools.cardMargin))
                        .frame(
                            maxWidth: .infinity, maxHeight: .infinity,
                            alignment: cardAlignment(for: rect, in: proxy.size)
                        )
                        .padding(Theme.Tools.cardMargin)
                        // At the top, the card sits under the hint line.
                        .padding(.top, Theme.Tools.hintTop + Theme.Tools.hintHeight)
                }
            }
        }
    }

    /// Centred just above the view, or just below when there's no room above.
    private func sizeTagCentre(for rect: CGRect, in size: CGSize) -> CGPoint {
        let offset = Theme.Tools.tagHeight / 2 + Theme.Tools.tagGap
        let above = rect.minY - offset
        let y = above - Theme.Tools.tagHeight / 2 >= 0 ? above : min(rect.maxY + offset, size.height - offset)
        return CGPoint(x: min(max(rect.midX, 0), size.width), y: y)
    }

    /// The card keeps out of the view's way: at the bottom, or at the top for a view low down.
    private func cardAlignment(for rect: CGRect, in size: CGSize) -> Alignment {
        rect.midY > size.height / 2 ? .top : .bottom
    }
}

/// Dashed lines from the view to the nearest left or right and top or bottom screen edge, each
/// tagged with its length in dp.
private struct EdgeGuides: View {
    let rect: CGRect
    let size: CGSize
    let edges: EdgeDistances
    let density: DensityScale

    var body: some View {
        let horizontal = edges.nearestHorizontal
        let vertical = edges.nearestVertical
        let hStart = CGPoint(x: horizontal.side == .left ? 0 : size.width, y: rect.midY)
        let hEnd = CGPoint(x: horizontal.side == .left ? rect.minX : rect.maxX, y: rect.midY)
        let vStart = CGPoint(x: rect.midX, y: vertical.side == .top ? 0 : size.height)
        let vEnd = CGPoint(x: rect.midX, y: vertical.side == .top ? rect.minY : rect.maxY)
        ZStack {
            Path { path in
                path.move(to: hStart)
                path.addLine(to: hEnd)
                path.move(to: vStart)
                path.addLine(to: vEnd)
            }
            .stroke(
                Color(nsColor: Theme.Palette.toolGuide),
                style: StrokeStyle(lineWidth: Theme.Tools.guideWidth, dash: Theme.Tools.guideDash))
            if horizontal.distance > 0 {
                ToolTag(text: "\(density.wholeDp(horizontal.distance))", colour: Theme.Palette.toolGuide)
                    .position(x: (hStart.x + hEnd.x) / 2, y: hStart.y)
            }
            if vertical.distance > 0 {
                ToolTag(text: "\(density.wholeDp(vertical.distance))", colour: Theme.Palette.toolGuide)
                    .position(x: vStart.x, y: (vStart.y + vEnd.y) / 2)
            }
        }
    }
}

/// The inspected view's details: what it says, its type, its frame in dp, its size in pixels
/// and its resource id.
struct InspectCard: View {
    let node: LayoutNode
    let density: DensityScale
    let isPinned: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Tools.cardRowGap) {
            Text(node.label ?? "No label")
                .font(Theme.Typeface.toolCardTitle)
                .foregroundStyle(
                    Color(nsColor: node.label == nil ? Theme.Palette.toolTextSecondary : Theme.Palette.toolText)
                )
                .lineLimit(1)
                .truncationMode(.tail)
            row("Type", node.shortClassName)
            row("Frame", density.frameText(node.frame))
            row("Pixels", DensityScale.pixelText(node.frame.size))
            if !node.resourceID.isEmpty { row("Id", node.resourceID) }
            if isPinned { row("Pinned", "Click it again to let go.") }
        }
        .padding(Theme.Tools.cardInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .toolSurface(in: RoundedRectangle(cornerRadius: Theme.Tools.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Tools.tagGap) {
            Text(key)
                .font(Theme.Typeface.toolCardKey)
                .foregroundStyle(Color(nsColor: Theme.Palette.toolTextSecondary))
                .frame(width: Theme.Tools.cardKeyWidth, alignment: .leading)
            Text(value)
                .font(Theme.Typeface.toolCardValue)
                .foregroundStyle(Color(nsColor: Theme.Palette.toolText))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

/// Measure: the dragged line with its length in dp and px.
struct MeasureOverlay: View {
    let tools: ToolsModel

    var body: some View {
        GeometryReader { proxy in
            if let line = tools.measurement, let scale = tools.scale {
                let start = scale.view(line.start)
                let end = scale.view(line.end)
                ZStack {
                    Path { path in
                        path.move(to: start)
                        path.addLine(to: end)
                    }
                    .stroke(Color(nsColor: Theme.Palette.toolGuide), lineWidth: Theme.Tools.outlineWidth)
                    ForEach([start, end], id: \.debugDescription) { point in
                        Circle()
                            .fill(Color(nsColor: Theme.Palette.toolGuide))
                            .frame(width: Theme.Tools.handleDiameter, height: Theme.Tools.handleDiameter)
                            .position(point)
                    }
                    if line.lengthPixels > 0 {
                        ToolTag(text: line.text(scale: tools.density), colour: Theme.Palette.toolGuide)
                            .position(tagCentre(start: start, end: end, in: proxy.size))
                    }
                }
            }
        }
    }

    /// Beside the line's middle: above a level line, to the right of an upright one.
    private func tagCentre(start: CGPoint, end: CGPoint, in size: CGSize) -> CGPoint {
        let middle = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let offset = Theme.Tools.tagHeight / 2 + Theme.Tools.tagGap
        let level = abs(end.x - start.x) >= abs(end.y - start.y)
        let point =
            level
            ? CGPoint(x: middle.x, y: middle.y - offset < offset ? middle.y + offset : middle.y - offset)
            : CGPoint(x: middle.x, y: middle.y)
        return CGPoint(x: min(max(point.x, 0), size.width), y: min(max(point.y, 0), size.height))
    }
}

/// Pick Colour: a loupe of the pixels around the pointer and the hex of the one under it.
struct ColourOverlay: View {
    let tools: ToolsModel

    var body: some View {
        GeometryReader { proxy in
            if let point = tools.hoverPoint, let colour = tools.colour, !tools.loupe.isEmpty {
                let side = CGFloat(tools.loupe.count) * Theme.Tools.loupeCell
                let centre = loupeCentre(for: point, side: side, in: proxy.size)
                VStack(spacing: Theme.Tools.loupeReadoutGap) {
                    Loupe(cells: tools.loupe)
                        .frame(width: side, height: side)
                    ColourReadout(colour: colour, copied: tools.copied)
                }
                .position(centre)
            }
        }
    }

    /// Below and to the right of the pointer, flipped to the other side near an edge.
    private func loupeCentre(for point: CGPoint, side: CGFloat, in size: CGSize) -> CGPoint {
        let reach = Theme.Tools.loupeOffset + side / 2
        let block = side + Theme.Tools.loupeReadoutGap + Theme.Tools.hintHeight
        let x = point.x + reach + side / 2 <= size.width ? point.x + reach : point.x - reach
        let y =
            point.y + Theme.Tools.loupeOffset + block <= size.height
            ? point.y + Theme.Tools.loupeOffset + block / 2 : point.y - Theme.Tools.loupeOffset - block / 2
        return CGPoint(x: x, y: y)
    }
}

private struct Loupe: View {
    let cells: [[PickedColour]]

    var body: some View {
        Canvas { context, size in
            let count = CGFloat(cells.count)
            guard count > 0 else { return }
            let cell = size.width / count
            for (row, colours) in cells.enumerated() {
                for (column, colour) in colours.enumerated() {
                    let rect = CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell)
                    context.fill(Path(rect), with: .color(Color(colour)))
                    context.stroke(
                        Path(rect), with: .color(Color(nsColor: Theme.Palette.loupeGrid)),
                        lineWidth: Theme.Tools.hairline)
                }
            }
            let middle = CGFloat(cells.count / 2) * cell
            context.stroke(
                Path(CGRect(x: middle, y: middle, width: cell, height: cell)),
                with: .color(Color(nsColor: Theme.Palette.loupeRing)), lineWidth: Theme.Tools.loupeCentreWidth)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Tools.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Tools.cardRadius, style: .continuous)
                .strokeBorder(Color(nsColor: Theme.Palette.loupeRing), lineWidth: Theme.Tools.loupeRingWidth)
        )
        .shadow(
            color: .black.opacity(Theme.Tools.shadowOpacity), radius: Theme.Tools.shadowRadius, y: Theme.Tools.shadowY
        )
        .accessibilityHidden(true)
    }
}

/// The hex under the pointer with a swatch, or "Copied." right after a click.
struct ColourReadout: View {
    let colour: PickedColour
    let copied: Bool

    var body: some View {
        HStack(spacing: Theme.Tools.loupeReadoutGap) {
            RoundedRectangle(cornerRadius: Theme.Tools.swatchRadius)
                .fill(Color(colour))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Tools.swatchRadius)
                        .strokeBorder(Color(nsColor: Theme.Palette.toolHairline), lineWidth: Theme.Tools.hairline)
                )
                .frame(width: Theme.Tools.swatchSize, height: Theme.Tools.swatchSize)
            Text(copied ? "Copied." : colour.hex)
                .font(Theme.Typeface.toolTag)
                .foregroundStyle(Color(nsColor: Theme.Palette.toolText))
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, Theme.Tools.hintPaddingH)
        .frame(height: Theme.Tools.hintHeight)
        .toolSurface(in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(copied ? "Copied." : colour.hex)
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
                .toolSurface(in: Capsule())
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
