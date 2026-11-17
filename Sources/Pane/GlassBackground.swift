import AppKit

/// The window's background, title bar included (`titleBarMatchesContent`).
///
/// Glass in both modes (Jatin's call for Pane, against the guide's solid paper in light): a
/// behind-window blur with an ink tint in dark (`inkGlass`) and a paper tint in light, strong
/// enough that text keeps 4.5:1 over a busy desktop. Reduce Transparency and Increase Contrast
/// make it solid ink or paper.
@MainActor
final class GlassBackgroundView: NSView {
    private let blur = NSVisualEffectView()
    private let tint = NSView()

    init(content: NSView) {
        super.init(frame: .zero)
        blur.blendingMode = .behindWindow
        blur.state = .active
        tint.wantsLayer = true
        for view in [blur, tint, content] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: leadingAnchor),
                view.trailingAnchor.constraint(equalTo: trailingAnchor),
                view.topAnchor.constraint(equalTo: topAnchor),
                view.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(displayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        update()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        update()
    }

    @objc private func displayOptionsChanged() { update() }

    /// Whether the glass shows: unless Reduce Transparency or Increase Contrast is on.
    nonisolated static func showsGlass(reduceTransparency: Bool, increaseContrast: Bool) -> Bool {
        !reduceTransparency && !increaseContrast
    }

    private func update() {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let workspace = NSWorkspace.shared
        var reduceTransparency = workspace.accessibilityDisplayShouldReduceTransparency
        var increaseContrast = workspace.accessibilityDisplayShouldIncreaseContrast
        #if DEBUG
            // Lets a background check see the solid fallback without changing system settings.
            reduceTransparency = reduceTransparency || UserDefaults.standard.bool(forKey: "PaneReduceTransparency")
            increaseContrast = increaseContrast || UserDefaults.standard.bool(forKey: "PaneIncreaseContrast")
        #endif
        let glass = Self.showsGlass(reduceTransparency: reduceTransparency, increaseContrast: increaseContrast)
        blur.isHidden = !glass
        blur.material = isDark ? Theme.Glass.darkMaterial : Theme.Glass.lightMaterial
        let opacity = isDark ? Theme.Glass.darkTintOpacity : Theme.Glass.lightTintOpacity
        tint.layer?.backgroundColor =
            glass
            ? Theme.Palette.surface.resolved(for: effectiveAppearance).withAlphaComponent(opacity).cgColor
            : Theme.Palette.surfaceSolid.resolved(for: effectiveAppearance).cgColor
    }
}

extension NSColor {
    /// This dynamic colour as it draws under an appearance.
    func resolved(for appearance: NSAppearance) -> NSColor {
        var resolved = self
        appearance.performAsCurrentDrawingAppearance { resolved = self.usingColorSpace(.sRGB) ?? self }
        return resolved
    }
}
