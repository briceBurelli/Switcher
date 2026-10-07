import AppKit

/// Frosted panel centered on screen. It never becomes key: the app you're leaving keeps focus
/// until a window is chosen, and the keyboard is read by the event tap.
final class SwitcherPanel: NSPanel {
    private var center: NSPoint = .zero
    private var presentation = 0

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 300),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        self.isFloatingPanel = true
        self.level = .popUpMenu
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.hidesOnDeactivate = false
        self.isMovable = false
        self.animationBehavior = .none
        self.appearance = NSAppearance(named: .darkAqua)
    }

    override var contentView: NSView? {
        didSet {
            contentView?.wantsLayer = true
            contentView?.layer?.cornerRadius = 26
            contentView?.layer?.cornerCurve = .continuous
            contentView?.layer?.masksToBounds = true
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func present(centeredIn area: NSRect) {
        presentation += 1
        center = NSPoint(x: area.midX, y: area.midY)
        setFrame(frame, display: false)
        ignoresMouseEvents = false
        // Shown at full opacity right away: a window ordered in at alpha 0 counts as hidden,
        // and SwiftUI then skipped drawing the cards until the next change (the second Tab)
        alphaValue = 1
        orderFrontRegardless()
        contentView?.needsLayout = true
        contentView?.layoutSubtreeIfNeeded()
        contentView?.needsDisplay = true
        displayIfNeeded()
    }

    /// Fades out, so even a quick ⌘Tab leaves a visible trace of the panel
    func dismiss() {
        guard isVisible else { return }
        ignoresMouseEvents = true
        let current = presentation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // A new ⌘Tab during the fade must not be hidden by this one
                guard let self, self.presentation == current else { return }
                self.orderOut(nil)
            }
        })
    }

    func resize(to size: CGSize) {
        setFrame(NSRect(x: 0, y: 0, width: ceil(size.width), height: ceil(size.height)), display: isVisible)
        invalidateShadow()
    }

    /// Every size change stays centered on the screen
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var frame = frameRect
        if center != .zero {
            frame.origin = NSPoint(x: round(center.x - frame.width / 2), y: round(center.y - frame.height / 2))
        }
        super.setFrame(frame, display: flag)
    }
}
