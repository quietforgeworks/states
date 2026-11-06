import AppKit
import QuartzCore

/// Native glass selection whose view geometry follows the selected segment.
final class GlassSegmentControl: NSControl {
    private let container = NSGlassEffectContainerView()
    private let content = NSView()
    private let selection = NSGlassEffectView()
    private let movementDuration: TimeInterval = 0.28
    private let movement = FrameAnimator()
    private var geometrySize: NSSize?
    private var buttons: [NSButton] = []
    private var index = 0
    var selectedSegment: Int {
        get { index }
        set { select(newValue, animated: false) }
    }
    init(labels: [String]) {
        super.init(frame: .zero)
        wantsLayer = true; layer?.cornerRadius = 18
        container.spacing = 8; container.contentView = content; addSubview(container)
        selection.style = .regular; selection.cornerRadius = 16
        selection.identifier = NSUserInterfaceItemIdentifier("states-tab-selection")
        selection.contentView = NSView(); selection.wantsLayer = true
        if #available(macOS 27.0, *) { selection.effectIsInteractive = true }
        // The glass container promotes native glass using NSView geometry.
        // Move the glass view itself so that its promoted effect follows it.
        content.addSubview(selection)
        for (tag, title) in labels.enumerated() {
            let button = NSButton(title: title, target: self, action: #selector(chose(_:)))
            button.tag = tag; button.isBordered = false; button.bezelStyle = .accessoryBarAction
            button.contentTintColor = .labelColor; button.font = .systemFont(ofSize: 13, weight: .medium)
            button.setAccessibilityRole(.radioButton)
            addSubview(button); buttons.append(button)
        }
        setAccessibilityElement(true); setAccessibilityRole(.tabGroup); setAccessibilityLabel("页面切换")
        setAccessibilityChildren(buttons)
        updateColors(); select(0, animated: false)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var acceptsFirstResponder: Bool { true }
    override func layout() {
        super.layout()
        guard geometrySize != bounds.size else { return }
        geometrySize = bounds.size
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.frame = bounds
        content.frame = container.bounds
        let width = segmentWidth
        for (index, button) in buttons.enumerated() {
            button.frame = NSRect(x: 3 + CGFloat(index) * width, y: 3,
                                  width: width, height: max(0, bounds.height - 6))
        }
        movement.cancel()
        selection.frame = NSRect(x: 3 + CGFloat(index) * width, y: 3, width: width,
                                 height: max(0, bounds.height - 6))
        CATransaction.commit()
    }
    private var segmentWidth: CGFloat {
        max(0, (bounds.width - 6) / CGFloat(max(1, buttons.count)))
    }
    private func moveSelection(animated: Bool) {
        movement.cancel()
        let source = selection.frame.origin
        let destination = NSPoint(x: 3 + CGFloat(index) * segmentWidth, y: 3)
        let animate = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && abs(source.x - destination.x) > 0.01
        movement.animate(duration: animate ? movementDuration : 0, window: window, update: { [weak self] progress in
            guard let self else { return }
            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = 0
            NSAnimationContext.current.allowsImplicitAnimation = false
            CATransaction.begin(); CATransaction.setDisableActions(true)
            self.selection.setFrameOrigin(NSPoint(x: source.x + (destination.x - source.x) * progress, y: 3))
            CATransaction.commit(); NSAnimationContext.endGrouping()
        }, observe: { [weak self] in
            guard let self else { return [] }
            return [Double(self.selection.frame.minX), Double(self.selection.layer?.presentation()?.frame.minX ?? -1)]
        }, completion: { [weak self] in
            guard let self else { return }
            MotionDiagnostics.save("glass", driver: self.movement.driverName, samples: self.movement.samples)
        })
    }
    private func select(_ value: Int, animated: Bool) {
        guard buttons.indices.contains(value) else { return }
        // Settle any actual size change using the previous selection first.
        layoutSubtreeIfNeeded()
        index = value
        for (i, button) in buttons.enumerated() {
            button.state = i == index ? .on : .off
            button.font = .systemFont(ofSize: 13, weight: i == index ? .semibold : .medium)
            button.setAccessibilityValue(i == index ? 1 : 0)
        }
        moveSelection(animated: animated)
    }
    @objc private func chose(_ sender: NSButton) {
        guard index != sender.tag else { return }
        select(sender.tag, animated: true); _ = sendAction(action, to: target)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 123 || event.keyCode == 124 {
            select(min(buttons.count - 1, max(0, index + (event.keyCode == 123 ? -1 : 1))), animated: true)
            _ = sendAction(action, to: target)
        } else { super.keyDown(with: event) }
    }
    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance { layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.055).cgColor }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateColors() }
}

