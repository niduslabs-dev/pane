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
            DeviceFrameView(model: model, layout: layout)
                .offset(x: layout.bodyOriginInWindow.x, y: layout.bodyOriginInWindow.y)
        }
        .frame(
            width: layout.windowContentSize.width, height: layout.windowContentSize.height, alignment: .topLeading
        )
        .background(Color(nsColor: Theme.Palette.surface))
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
                ToolButton(symbol: "arrow.trianglehead.2.clockwise.rotate.90", label: "Rotate")
                    .disabled(!toolsEnabled)
                ToolButton(symbol: "camera", label: "Save screenshot")
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
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
        } label: {
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
/// buttons with their wider invisible hit areas.
struct DeviceFrameView: View {
    let model: PaneModel
    let layout: DeviceFrameLayout
    @State private var hovered: FrameButton?

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(layout.buttons, id: \.button) { button in
                buttonShape(button)
            }
            bodyShape(layout.bodyRect)
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
            ForEach(layout.buttons, id: \.button) { button in
                hitArea(button)
            }
        }
        .frame(
            width: layout.bodyRect.width + Theme.Frame.buttonHitDepth, height: layout.bodyRect.height,
            alignment: .topLeading)
    }

    private func bodyShape(_ rect: CGRect) -> some View {
        RoundedRectangle(cornerRadius: Theme.Frame.bodyRadius)
            .fill(Color(nsColor: Theme.Palette.frameBody))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Frame.bodyRadius)
                    .strokeBorder(Color(nsColor: Theme.Palette.frameEdge), lineWidth: Theme.Frame.edgeWidth)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Frame.bodyRadius)
                    .inset(by: Theme.Frame.innerEdgeInset)
                    .strokeBorder(Color(nsColor: Theme.Palette.frameInnerEdge), lineWidth: Theme.Frame.innerEdgeWidth)
            )
            .frame(width: rect.width, height: rect.height)
    }

    @ViewBuilder private var screen: some View {
        let rect = layout.screenRect
        ZStack {
            ScreenRepresentable(view: model.screenView)
            switch model.status {
            case .noEmulator: message("No emulator running.")
            case .failed: message("Can't connect to the emulator.")
            case .connecting, .live: EmptyView()
            }
        }
        .frame(width: rect.width, height: rect.height)
        .offset(x: rect.minX, y: rect.minY)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typeface.screenMessage)
            .foregroundStyle(Color(nsColor: Theme.Palette.screenMessage))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: Theme.Palette.screenEmpty))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Frame.screenRadius))
            .allowsHitTesting(false)
    }

    private func buttonShape(_ button: DeviceFrameLayout.Button) -> some View {
        let isHovered = hovered == button.button && button.button == .power
        let depth = isHovered ? Theme.Frame.buttonDepthHover : Theme.Frame.buttonDepth
        let radius = Theme.Frame.buttonCornerRadius
        // The volume rocker reads as one piece: only its outer ends are rounded.
        let radii: RectangleCornerRadii =
            switch button.button {
            case .power: RectangleCornerRadii(bottomTrailing: radius, topTrailing: radius)
            case .volumeUp: RectangleCornerRadii(topTrailing: radius)
            case .volumeDown: RectangleCornerRadii(bottomTrailing: radius)
            }
        return UnevenRoundedRectangle(cornerRadii: radii)
            .fill(Color(nsColor: isHovered ? Theme.Palette.frameButtonHover : Theme.Palette.frameButton))
            .frame(width: depth, height: button.visibleRect.height)
            .offset(x: button.visibleRect.minX, y: button.visibleRect.minY)
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
