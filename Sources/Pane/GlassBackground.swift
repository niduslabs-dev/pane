import AppKit

/// The window's background, title bar included (`titleBarMatchesContent`).
///
/// Dark mode is ink glass (`inkGlass`): a behind-window blur with an ink tint over it. Light mode
/// is solid paper. Reduce Transparency and Increase Contrast make dark mode solid ink.
@MainActor
final class GlassBackgroundView: NSView {
    private let blur = NSVisualEffectView()
    private let tint = NSView()

    init(content: NSView) {
        super.init(frame: .zero)
        blur.material = Theme.Glass.material
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.appearance = NSAppearance(named: .darkAqua)
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

    /// Whether the glass shows: dark mode, with neither Reduce Transparency nor Increase Contrast.
    nonisolated static func showsGlass(isDark: Bool, reduceTransparency: Bool, increaseContrast: Bool) -> Bool {
        isDark && !reduceTransparency && !increaseContrast
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
        let glass = Self.showsGlass(
            isDark: isDark, reduceTransparency: reduceTransparency, increaseContrast: increaseContrast)
        blur.isHidden = !glass
        let color = Theme.Palette.surface.resolved(for: effectiveAppearance)
        tint.layer?.backgroundColor = (glass ? color.withAlphaComponent(Theme.Glass.tintOpacity) : color).cgColor
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
