import Cocoa

final class HUD {
    private var window: NSWindow?
    private var hideTimer: Timer?

    /// Show a floating HUD near the menu bar with an icon and message.
    func show(_ message: String, icon: String, duration: TimeInterval = 3.0) {
        DispatchQueue.main.async { [self] in
            hideTimer?.invalidate()
            window?.close()

            let panel = NSPanel(
                contentRect: .zero,
                styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.titlebarAppearsTransparent = true
            panel.titleVisibility = .hidden
            panel.isMovableByWindowBackground = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.isReleasedWhenClosed = false

            // Content
            let container = NSVisualEffectView()
            container.material = .hudWindow
            container.state = .active
            container.wantsLayer = true
            container.layer?.cornerRadius = 10

            let iconLabel = NSTextField(labelWithString: icon)
            iconLabel.font = .systemFont(ofSize: 24)
            iconLabel.alignment = .center
            iconLabel.setContentHuggingPriority(.required, for: .horizontal)

            let textLabel = NSTextField(wrappingLabelWithString: message)
            textLabel.font = .systemFont(ofSize: 14)
            textLabel.textColor = .labelColor
            textLabel.maximumNumberOfLines = 3
            textLabel.preferredMaxLayoutWidth = 280

            let stack = NSStackView(views: [iconLabel, textLabel])
            stack.orientation = .horizontal
            stack.spacing = 10
            stack.alignment = .centerY
            stack.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)

            container.addSubview(stack)
            stack.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: container.topAnchor),
                stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                stack.widthAnchor.constraint(lessThanOrEqualToConstant: 350),
                stack.widthAnchor.constraint(greaterThanOrEqualToConstant: 150),
            ])

            panel.contentView = container

            // Size and position: top-right of screen
            let size = container.fittingSize
            if let screen = NSScreen.main {
                let x = screen.visibleFrame.maxX - size.width - 16
                let y = screen.visibleFrame.maxY - size.height - 8
                panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
            }

            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                panel.animator().alphaValue = 1
            }

            self.window = panel

            hideTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                self?.hide()
            }
        }
    }

    func hide() {
        hideTimer?.invalidate()
        hideTimer = nil
        guard let w = window else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            w.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            w.close()
            self?.window = nil
        })
    }
}
