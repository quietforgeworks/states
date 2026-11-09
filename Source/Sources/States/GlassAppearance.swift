import AppKit
import StatesCore

extension GlassAppearance {
    var tint: NSColor? {
        guard let tintHex, let rgb = UInt32(tintHex.dropFirst(), radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
                       green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: 1)
    }
}

private final class GlassBackingView: NSView {
    var color = NSColor.windowBackgroundColor { didSet { needsDisplay = true } }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) { color.setFill(); dirtyRect.fill() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

final class PersonalizedGlassSurface: NSView {
    let regular = NSGlassEffectView()
    private let material = NSGlassEffectView()
    private let backing = GlassBackingView(), reinforcement = GlassBackingView()
    private let tintOverlay = GlassBackingView()
    private(set) var configuration = GlassAppearance.standard
    var usesNativeContentHierarchy: Bool { regular.contentView === content }
    var backgroundOpacity: CGFloat { material.isHidden ? 0 : material.alphaValue }
    private var content: NSView?
    var cornerRadius: CGFloat = 20 {
        didSet { regular.cornerRadius = cornerRadius; material.cornerRadius = cornerRadius; layer?.cornerRadius = cornerRadius }
    }
    var contentView: NSView? {
        get { content }
        set {
            content?.removeFromSuperview(); regular.contentView = nil; content = newValue
            placeContent(); needsLayout = true
        }
    }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; layer?.cornerRadius = cornerRadius; layer?.masksToBounds = true
        regular.style = .regular; regular.cornerRadius = cornerRadius
        material.style = .regular; material.cornerRadius = cornerRadius; material.contentView = NSView()
        for view in [backing, material, reinforcement, regular] { addSubview(view) }
        material.isHidden = true; backing.isHidden = true; reinforcement.isHidden = true; tintOverlay.isHidden = true
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override func layout() {
        super.layout()
        for view in [backing, material, regular, reinforcement, tintOverlay] { view.frame = bounds }
        content?.frame = bounds
    }
    private func placeContent() {
        guard let content else { return }
        content.frame = bounds; content.autoresizingMask = [.width, .height]
        if regular.contentView !== content { content.removeFromSuperview(); regular.contentView = content }
        for view in [reinforcement, tintOverlay, backing] where view.superview !== content {
            view.removeFromSuperview(); content.addSubview(view, positioned: .below, relativeTo: nil)
        }
    }
    func apply(_ next: GlassAppearance) {
        guard next != configuration else { return }
        configuration = next
        NSAnimationContext.beginGrouping(); NSAnimationContext.current.duration = 0
        NSAnimationContext.current.allowsImplicitAnimation = false
        regular.tintColor = next.tint?.withAlphaComponent(0.32)
        material.tintColor = next.tint?.withAlphaComponent(0.32)
        regular.style = next.hasNativeGeometry ? .regular : .clear
        regular.alphaValue = 1
        material.alphaValue = next.regularOpacity
        material.isHidden = next.hasNativeGeometry || next.regularOpacity == 0
        backing.isHidden = next.opaqueBacking == 0
        backing.color = (next.tint ?? .windowBackgroundColor).withAlphaComponent(next.opaqueBacking)
        reinforcement.isHidden = next.reinforcement == 0
        reinforcement.color = (next.tint ?? .windowBackgroundColor).withAlphaComponent(next.reinforcement)
        tintOverlay.isHidden = next.tint == nil || next.transparency == 1
        tintOverlay.color = (next.tint ?? .clear).withAlphaComponent(min(0.55, 0.36 * next.strength * (1 - next.transparency)))
        placeContent(); needsLayout = true
        NSAnimationContext.endGrouping()
    }
}

final class GlassAppearancePreview: NSView {
    let glass = PersonalizedGlassSurface(frame: .zero)
    private let content = FlippedView()
    private let tabs = GlassSegmentControl(labels: ["概览", "电源"])
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; layer?.cornerRadius = 12; layer?.masksToBounds = true
        glass.cornerRadius = 16; glass.contentView = content; addSubview(glass)
        let title = label("液态玻璃", size: 14, weight: .semibold)
        title.frame = NSRect(x: 20, y: 14, width: 180, height: 22); content.addSubview(title)
        tabs.frame = NSRect(x: 16, y: 46, width: 260, height: 34); content.addSubview(tabs)
        setAccessibilityLabel("液态玻璃效果预览")
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let gradient = NSGradient(colors: [NSColor.systemTeal.withAlphaComponent(0.6),
            NSColor.systemPurple.withAlphaComponent(0.45), NSColor.systemOrange.withAlphaComponent(0.45)])!
        gradient.draw(in: bounds, angle: 25)
    }
    override func layout() {
        super.layout()
        glass.frame = NSRect(x: 22, y: 18, width: max(0, bounds.width - 44), height: max(0, bounds.height - 36))
        tabs.frame.size.width = max(0, glass.bounds.width - 32)
    }
    func apply(_ appearance: GlassAppearance) { glass.apply(appearance); tabs.applyGlassAppearance(appearance) }
}
