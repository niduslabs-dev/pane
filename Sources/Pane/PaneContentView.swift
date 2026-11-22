import PaneCore
import SwiftUI

/// The whole window content: the title bar, the drawn device and the toolbar under it, laid out
/// from the model's `DeviceFrameLayout` so the window is exactly the board's shape for any size.
/// The chrome (`TitleBar`, `DeviceToolbar`) lives in `Chrome.swift` and only reads the model.
struct PaneContentView: View {
    let model: PaneModel

    var body: some View {
        let layout = model.layout
        ZStack(alignment: .topLeading) {
            TitleBar(model: model)
                .frame(width: layout.windowContentSize.width, height: Theme.Window.titleRowHeight)
            if model.status == .failed {
                ErrorCard(model: model)
                    .frame(
                        width: layout.windowContentSize.width - 2 * Theme.Window.contentInset,
                        height: layout.windowContentSize.height - Theme.Window.titleRowHeight
                            - Theme.Toolbar.bandHeight
                    )
                    .offset(x: Theme.Window.contentInset, y: Theme.Window.titleRowHeight)
            } else {
                DeviceFrameView(model: model, layout: layout)
            }
            DeviceToolbar(model: model)
                .frame(width: layout.windowContentSize.width, height: Theme.Toolbar.bandHeight)
                .offset(y: layout.windowContentSize.height - Theme.Toolbar.bandHeight)
            if let menu = model.menu {
                PaneMenuLayer(model: model, menu: menu)
            }
        }
        .frame(
            width: layout.windowContentSize.width, height: layout.windowContentSize.height, alignment: .topLeading
        )
        .displayOptions()
    }
}

/// The drawn device: body with its edge rings, the live screen, and the side
/// buttons with their wider invisible hit areas. Every rect comes from the layout, in window
/// coordinates, for the current size and orientation.
struct DeviceFrameView: View {
    let model: PaneModel
    let layout: DeviceFrameLayout
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(layout.buttons, id: \.button) { button in
                buttonShape(button)
            }
            bodyShape
            screen
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
            Group {
                switch model.status {
                case .noEmulator: NoEmulatorScreen(model: model)
                case .starting, .booting, .connecting: ProgressScreen(model: model)
                case .live, .failed: EmptyView()
                }
            }
            if model.status == .live {
                ToolOverlay(tools: model.tools)
            }
            CaptureFlash(model: model)
            NoticePill(model: model)
            DropLayer(drop: model.drop, screenRadius: layout.screenRadius)
        }
        .frame(width: rect.width, height: rect.height)
        .coordinateSpace(.named(DropLayer.space))
        .clipShape(RoundedRectangle(cornerRadius: layout.screenRadius))
        .offset(x: rect.minX, y: rect.minY)
    }

    /// A side button as the iOS Simulator draws them: nearly flush with a faint light outline,
    /// sliding out when the pointer comes near and pushing in while pressed. Reduce Motion keeps
    /// it in place and changes only the fill.
    private func buttonShape(_ button: DeviceFrameLayout.Button) -> some View {
        let isPressed = model.heldButtons.contains(button.button)
        let isNear = model.status == .live && model.nearButton == button.button
        let depth =
            reduceMotion
            ? Theme.Frame.buttonDepth
            : (isPressed
                ? Theme.Frame.buttonDepthPressed : (isNear ? Theme.Frame.buttonDepthNear : Theme.Frame.buttonDepth))
        let rect = button.visibleRect(depth: depth)
        let radius = Theme.Frame.buttonCornerRadius
        let corners = button.roundedCorners
        let radii = RectangleCornerRadii(
            topLeading: corners.contains(.topLeft) ? radius : 0,
            bottomLeading: corners.contains(.bottomLeft) ? radius : 0,
            bottomTrailing: corners.contains(.bottomRight) ? radius : 0,
            topTrailing: corners.contains(.topRight) ? radius : 0)
        let shape = UnevenRoundedRectangle(cornerRadii: radii)
        return
            shape
            .fill(Color(nsColor: isNear || isPressed ? Theme.Palette.frameButtonNear : Theme.Palette.frameButton))
            .overlay(
                shape.strokeBorder(
                    Color(nsColor: Theme.Palette.frameButtonEdge), lineWidth: Theme.Frame.buttonEdgeWidth)
            )
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
            .animation(
                .spring(response: Theme.Frame.buttonSpringResponse, dampingFraction: Theme.Frame.buttonSpringDamping),
                value: depth)
    }

    private func hitArea(_ button: DeviceFrameLayout.Button) -> some View {
        FrameButtonHitArea(
            label: helpText(button.button),
            onPress: { isDown in model.setButton(button.button, isDown: isDown) }
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
