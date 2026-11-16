import PaneCore
import SwiftUI

/// The whole window content: the title row over the drawn device, laid out from the model's
/// `DeviceFrameLayout` so the window is exactly the board's shape for any screen size.
struct PaneContentView: View {
    let model: PaneModel

    var body: some View {
        let layout = model.layout
        ZStack(alignment: .topLeading) {
            TitleRow(model: model)
                .frame(width: layout.windowContentSize.width, height: Theme.Window.titleRowHeight)
            if model.status == .failed {
                ErrorCard(model: model)
                    .frame(
                        width: layout.windowContentSize.width - 2 * Theme.Window.contentInset,
                        height: layout.windowContentSize.height - Theme.Window.titleRowHeight
                            - Theme.Window.contentInset
                    )
                    .offset(x: Theme.Window.contentInset, y: Theme.Window.titleRowHeight)
            } else {
                DeviceFrameView(model: model, layout: layout)
            }
        }
        .frame(
            width: layout.windowContentSize.width, height: layout.windowContentSize.height, alignment: .topLeading
        )
    }
}

/// Traffic lights (the system's), the device name and model centred, then the tools.
struct TitleRow: View {
    let model: PaneModel

    var body: some View {
        let toolsEnabled = model.status == .live
        HStack(spacing: Theme.Window.titleRowGap) {
            Color.clear.frame(width: Theme.Window.trafficLightsWidth)
            VStack(spacing: Theme.Window.titleLineSpacing) {
                Text(model.title)
                    .font(Theme.Typeface.windowTitle)
                    .foregroundStyle(Color(nsColor: Theme.Palette.text))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(model.meta)
                    .font(Theme.Typeface.meta)
                    .foregroundStyle(Color(nsColor: Theme.Palette.textSecondary))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            HStack(spacing: Theme.Window.toolSpacing) {
                // Inert in the spike: rotate, screenshot and the More menu come with v1.
                ToolButton(symbol: "arrow.trianglehead.2.clockwise.rotate.90", label: "Rotate") { model.rotate() }
                    .disabled(!toolsEnabled)
                ToolButton(symbol: "camera", label: "Save screenshot") { model.saveScreenshot() }
                    .disabled(!toolsEnabled)
                ToolButton(symbol: "ellipsis", label: "More")
            }
            .frame(width: Theme.Window.toolsWidth, alignment: .trailing)
        }
        .padding(.leading, Theme.Window.titleRowLeadingPadding)
        .padding(.trailing, Theme.Window.titleRowTrailingPadding)
    }
}

struct ToolButton: View {
    let symbol: String
    let label: String
    var action: () -> Void = {}
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: Theme.Window.toolIconSize))
                .foregroundStyle(Color(nsColor: Theme.Palette.icon))
                .frame(width: Theme.Window.toolButtonSize, height: Theme.Window.toolButtonSize)
                .contentShape(RoundedRectangle(cornerRadius: Theme.Window.toolButtonRadius))
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : Theme.Window.disabledToolOpacity)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// The drawn device: body with its edge rings, the live screen, the punch hole, and the side
/// buttons with their wider invisible hit areas. Every rect comes from the layout, in window
/// coordinates, for the current size and orientation.
struct DeviceFrameView: View {
    let model: PaneModel
    let layout: DeviceFrameLayout
    @State private var hovered: FrameButton?

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(layout.buttons, id: \.button) { button in
                buttonShape(button)
            }
            bodyShape
            screen
            Circle()
                .fill(Color(nsColor: Theme.Palette.punchHole))
                .overlay(
                    Circle().strokeBorder(
                        Color(nsColor: Theme.Palette.punchHoleRing), lineWidth: Theme.Frame.punchHoleRingWidth)
                )
                .frame(width: layout.punchHoleRect.width, height: layout.punchHoleRect.height)
                .offset(x: layout.punchHoleRect.minX, y: layout.punchHoleRect.minY)
                .allowsHitTesting(false)
            if model.status == .live {
                ForEach(layout.buttons, id: \.button) { button in
                    hitArea(button)
                }
            }
        }
        .frame(width: layout.windowContentSize.width, height: layout.windowContentSize.height, alignment: .topLeading)
    }

    private var bodyShape: some View {
        let rect = layout.bodyRect
        let radius = layout.bodyRadius
        return RoundedRectangle(cornerRadius: radius)
            .fill(Color(nsColor: Theme.Palette.frameBody))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(Color(nsColor: Theme.Palette.frameEdge), lineWidth: Theme.Frame.edgeWidth)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .inset(by: Theme.Frame.innerEdgeInset)
                    .strokeBorder(Color(nsColor: Theme.Palette.frameInnerEdge), lineWidth: Theme.Frame.innerEdgeWidth)
            )
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
    }

    @ViewBuilder private var screen: some View {
        let rect = layout.screenRect
        ZStack {
            ScreenRepresentable(view: model.screenView, cornerRadius: layout.screenRadius)
            switch model.status {
            case .noEmulator: NoEmulatorScreen(model: model)
            case .starting, .booting, .connecting: ProgressScreen(model: model)
            case .live, .failed: EmptyView()
            }
        }
        .frame(width: rect.width, height: rect.height)
        .clipShape(RoundedRectangle(cornerRadius: layout.screenRadius))
        .offset(x: rect.minX, y: rect.minY)
    }

    private func buttonShape(_ button: DeviceFrameLayout.Button) -> some View {
        let isHovered = hovered == button.button && button.button == .power
        let rect = isHovered ? button.visibleRect(depth: Theme.Frame.buttonDepthHover) : button.visibleRect
        let radius = Theme.Frame.buttonCornerRadius
        let corners = button.roundedCorners
        let radii = RectangleCornerRadii(
            topLeading: corners.contains(.topLeft) ? radius : 0,
            bottomLeading: corners.contains(.bottomLeft) ? radius : 0,
            bottomTrailing: corners.contains(.bottomRight) ? radius : 0,
            topTrailing: corners.contains(.topRight) ? radius : 0)
        return UnevenRoundedRectangle(cornerRadii: radii)
            .fill(Color(nsColor: isHovered ? Theme.Palette.frameButtonHover : Theme.Palette.frameButton))
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
    }

    private func hitArea(_ button: DeviceFrameLayout.Button) -> some View {
        FrameButtonHitArea(
            label: helpText(button.button),
            onPress: { isDown in model.setButton(button.button, isDown: isDown) },
            onHover: { inside in
                hovered = inside ? button.button : (hovered == button.button ? nil : hovered)
            }
        )
        .frame(width: button.hitRect.width, height: button.hitRect.height)
        .offset(x: button.hitRect.minX, y: button.hitRect.minY)
    }

    private func helpText(_ button: FrameButton) -> String {
        switch button {
        case .power: "Power. Hold for a long press."
        case .volumeUp: "Volume up"
        case .volumeDown: "Volume down"
        }
    }
}
