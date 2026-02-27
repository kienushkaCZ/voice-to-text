import Cocoa

final class HUD {
    private var window: NSWindow?
    private var hideTimer: Timer?
    private var progressTimer: Timer?
    private var textField: NSTextField?
    private var progressIndicator: NSProgressIndicator?
    private var progressStartTime: TimeInterval = 0
    private var progressEstimatedDuration: TimeInterval = 10
    private var baseMessage: String = ""
    private var levelView: AudioLevelView?

    /// Show a floating HUD near the menu bar with an icon and message.
    func show(_ message: String, icon: String, duration: TimeInterval = 3.0) {
        DispatchQueue.main.async { [self] in
            invalidateTimers()
            window?.close()

            let panel = createPanel()
            let container = createContent(icon: icon, message: message, mode: .simple)
            panel.contentView = container
            positionAndPresent(panel: panel, container: container)

            self.window = panel

            hideTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                self?.hide()
            }
        }
    }

    /// Show a recording HUD with animated audio level bars. Stays visible until replaced.
    func showRecording(_ message: String, icon: String) {
        DispatchQueue.main.async { [self] in
            invalidateTimers()
            window?.close()

            let panel = createPanel()
            let container = createContent(icon: icon, message: message, mode: .recording)
            panel.contentView = container
            positionAndPresent(panel: panel, container: container)

            self.window = panel
        }
    }

    /// Update the audio level meter (call from audio callback on main thread).
    func updateAudioLevel(_ level: Float) {
        levelView?.updateLevel(level)
    }

    /// Show a floating HUD with a progress bar. Stays visible until replaced or hidden.
    func showWithProgress(_ message: String, icon: String, estimatedDuration: TimeInterval) {
        DispatchQueue.main.async { [self] in
            invalidateTimers()
            window?.close()

            self.baseMessage = message
            self.progressStartTime = ProcessInfo.processInfo.systemUptime
            self.progressEstimatedDuration = max(estimatedDuration, 2.0)

            let panel = createPanel()
            let container = createContent(icon: icon, message: message, mode: .progress)
            panel.contentView = container
            positionAndPresent(panel: panel, container: container)

            self.window = panel
            progressIndicator?.doubleValue = 0

            progressTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
                self?.tickProgress()
            }
        }
    }

    func hide() {
        invalidateTimers()
        guard let w = window else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            w.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            w.close()
            self?.window = nil
            self?.textField = nil
            self?.progressIndicator = nil
            self?.levelView = nil
        })
    }

    // MARK: - Private

    private enum ContentMode {
        case simple
        case recording
        case progress
    }

    private func invalidateTimers() {
        hideTimer?.invalidate()
        hideTimer = nil
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func tickProgress() {
        let elapsed = ProcessInfo.processInfo.systemUptime - progressStartTime
        let est = progressEstimatedDuration

        let progress: Double
        if elapsed <= est {
            progress = (elapsed / est) * 80.0
        } else {
            progress = 80.0 + 15.0 * (1.0 - exp(-(elapsed - est) / est))
        }

        progressIndicator?.doubleValue = min(progress, 95.0)

        let seconds = Int(elapsed)
        textField?.stringValue = "\(baseMessage) \(seconds)s"
    }

    private func createPanel() -> NSPanel {
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
        return panel
    }

    private func createContent(icon: String, message: String, mode: ContentMode) -> NSVisualEffectView {
        let container = NSVisualEffectView()
        container.material = .hudWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 10

        let iconLabel = NSTextField(labelWithString: icon)
        iconLabel.font = .systemFont(ofSize: 24)
        iconLabel.alignment = .center
        iconLabel.setContentHuggingPriority(.required, for: .horizontal)

        let rightColumn: NSView

        switch mode {
        case .recording:
            let textLabel = NSTextField(labelWithString: message)
            textLabel.font = .systemFont(ofSize: 14)
            textLabel.textColor = .labelColor
            self.textField = textLabel

            let lv = AudioLevelView()
            self.levelView = lv

            let row = NSStackView(views: [textLabel, lv])
            row.orientation = .horizontal
            row.spacing = 10
            row.alignment = .centerY
            rightColumn = row

        case .progress:
            let textLabel = NSTextField(labelWithString: message)
            textLabel.font = .systemFont(ofSize: 14)
            textLabel.textColor = .labelColor
            textLabel.lineBreakMode = .byTruncatingTail
            self.textField = textLabel

            let progress = NSProgressIndicator()
            progress.style = .bar
            progress.minValue = 0
            progress.maxValue = 100
            progress.doubleValue = 0
            progress.isIndeterminate = false
            progress.controlSize = .small
            self.progressIndicator = progress

            let vertStack = NSStackView(views: [textLabel, progress])
            vertStack.orientation = .vertical
            vertStack.alignment = .leading
            vertStack.spacing = 6

            progress.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                progress.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            ])

            rightColumn = vertStack

        case .simple:
            let textLabel = NSTextField(wrappingLabelWithString: message)
            textLabel.font = .systemFont(ofSize: 14)
            textLabel.textColor = .labelColor
            textLabel.maximumNumberOfLines = 3
            textLabel.preferredMaxLayoutWidth = 280
            self.textField = textLabel
            rightColumn = textLabel
        }

        let stack = NSStackView(views: [iconLabel, rightColumn])
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
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 380),
            stack.widthAnchor.constraint(greaterThanOrEqualToConstant: 150),
        ])

        return container
    }

    private func positionAndPresent(panel: NSPanel, container: NSVisualEffectView) {
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
    }
}

// MARK: - Audio Level Meter View

private class AudioLevelView: NSView {
    private let barCount = 5
    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 2
    private let maxBarHeight: CGFloat = 16
    private let minBarHeight: CGFloat = 2
    private var barLevels: [CGFloat]

    init() {
        barLevels = Array(repeating: 0, count: barCount)
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        let width = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barSpacing
        return NSSize(width: width, height: maxBarHeight)
    }

    func updateLevel(_ level: Float) {
        let normalized = CGFloat(min(level * 8, 1.0))

        for i in 0..<barCount {
            let variation = CGFloat.random(in: 0.5...1.0)
            let target = normalized * variation
            // Fast attack, slow decay
            barLevels[i] = target > barLevels[i] ? target : barLevels[i] * 0.55 + target * 0.45
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        for i in 0..<barCount {
            let height = minBarHeight + (maxBarHeight - minBarHeight) * barLevels[i]
            let x = CGFloat(i) * (barWidth + barSpacing)
            let y = (bounds.height - height) / 2

            let rect = NSRect(x: x, y: y, width: barWidth, height: height)
            let path = NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5)
            NSColor.systemGreen.withAlphaComponent(0.9).setFill()
            path.fill()
        }
    }
}
