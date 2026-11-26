import AppKit

/// Powiadomienie rysowane własnym oknem zamiast `UNUserNotificationCenter`:
/// pojawia się natychmiast, nie wymaga zgody na powiadomienia i nie zostaje
/// w Centrum powiadomień.
@MainActor
final class HUD {
    static let shared = HUD()

    private var panel: NSPanel?
    private var dismissWork: DispatchWorkItem?
    var onClick: (() -> Void)?

    private init() {}

    struct Content {
        var title: String
        var subtitle: String
        var symbol: String
        var tint: NSColor
        var duration: TimeInterval = 4
    }

    func show(_ content: Content) {
        dismissWork?.cancel()
        panel?.orderOut(nil)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 96),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.contentView = makeContentView(content)

        position(panel)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 1
        }

        self.panel = panel
        scheduleDismiss(after: content.duration)
    }

    func dismiss() {
        dismissWork?.cancel()
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                panel.orderOut(nil)
                if self?.panel === panel { self?.panel = nil }
            }
        }
    }

    private func scheduleDismiss(after delay: TimeInterval) {
        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Prawy górny róg ekranu, na którym jest kursor — tam, gdzie system pokazuje powiadomienia.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: frame.maxX - size.width - 16, y: frame.maxY - size.height - 16))
    }

    private func makeContentView(_ content: Content) -> NSView {
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: content.symbol, accessibilityDescription: nil)
        icon.symbolConfiguration = .init(pointSize: 22, weight: .semibold)
        icon.contentTintColor = content.tint
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: content.title)
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        title.lineBreakMode = .byTruncatingMiddle
        title.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = NSTextField(labelWithString: content.subtitle)
        subtitle.font = .systemFont(ofSize: 11, weight: .regular)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [title, subtitle])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false

        effect.addSubview(icon)
        effect.addSubview(stack)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 16),
            icon.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: effect.trailingAnchor, constant: -16),
            stack.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
        ])

        let click = NSClickGestureRecognizer(target: self, action: #selector(handleClick))
        effect.addGestureRecognizer(click)
        return effect
    }

    @objc private func handleClick() {
        onClick?()
        dismiss()
    }
}
