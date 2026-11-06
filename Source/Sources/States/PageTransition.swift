import AppKit
import QuartzCore

/// Only the destination receives input while both pages are being composited.
final class PageTransitionHost: NSView {
    weak var activePage: NSView?
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; layer?.masksToBounds = true
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard !isHidden, bounds.contains(local) else { return nil }
        return activePage?.hitTest(local) ?? self
    }
}

/// Keep real pages and their geometry stable, applying intermediate view alpha
/// values at display cadence rather than animating AppKit-owned backing layers.
final class PageTransitionController {
    static let duration: TimeInterval = 0.28
    private let host: PageTransitionHost
    private let pages: [NSView]
    private let animator = FrameAnimator()
    private var generation: UInt64 = 0
    private var completion: (() -> Void)?
    private(set) var selectedIndex: Int
    private(set) var isAnimating = false

    init(host: PageTransitionHost, pages: [NSView], initial: Int = 0) {
        precondition(!pages.isEmpty && pages.indices.contains(initial))
        self.host = host; self.pages = pages; selectedIndex = initial
        for page in pages { page.wantsLayer = true; if page.superview !== host { host.addSubview(page) } }
        settle()
    }
    func transition(to index: Int, animated: Bool, alongside: @escaping (CGFloat) -> Void = { _ in }, completion: @escaping () -> Void = {}) {
        precondition(Thread.isMainThread)
        guard pages.indices.contains(index) else { return }
        if index == selectedIndex && isAnimating { self.completion = completion; return }
        let starts = pages.map { $0.alphaValue }
        generation &+= 1; let token = generation
        animator.cancel()
        self.completion = completion; selectedIndex = index
        isAnimating = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            && starts.enumerated().contains { abs($0.element - ($0.offset == index ? 1 : 0)) > 0.001 }
        host.activePage = pages[index]
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for (i, page) in pages.enumerated() {
            page.setAccessibilityHidden(i != index)
            page.isHidden = isAnimating ? (i != index && starts[i] <= 0) : i != index
        }
        if isAnimating {
            // Warm the newly visible page before its first blended frame.
            pages[index].alphaValue = 1
            pages[index].layoutSubtreeIfNeeded(); pages[index].displayIfNeeded()
            pages[index].alphaValue = starts[index]
        } else {
            alongside(1)
            applyFinalState()
        }
        CATransaction.commit()
        guard isAnimating else {
            let finished = self.completion; self.completion = nil; finished?(); return
        }
        animator.animate(duration: Self.duration, window: host.window, update: { [weak self] progress in
            guard let self, self.generation == token else { return }
            CATransaction.begin(); CATransaction.setDisableActions(true)
            alongside(progress)
            for (i, page) in self.pages.enumerated() {
                let target: CGFloat = i == index ? 1 : 0
                page.alphaValue = starts[i] + (target - starts[i]) * progress
            }
            CATransaction.commit()
        }, observe: { [weak self] in
            guard let self else { return [] }
            return self.pages.map { Double($0.alphaValue) }
                + self.pages.map { Double($0.layer?.presentation()?.opacity ?? -1) }
                + [Double(self.host.bounds.height), Double(self.host.window?.frame.height ?? 0)]
                + self.anchorDiagnostics()
        }, completion: { [weak self] in
            guard let self, self.generation == token else { return }
            MotionDiagnostics.save("page", driver: self.animator.driverName, samples: self.animator.samples)
            let finished = self.completion; self.completion = nil
            self.isAnimating = false
            CATransaction.begin(); CATransaction.setDisableActions(true)
            self.applyFinalState()
            CATransaction.commit()
            finished?()
        })
    }
    private func anchorDiagnostics() -> [Double] {
        guard let window = host.window else { return [] }
        let top = host.convert(NSPoint(x: 0, y: 0), to: nil)
        let screen = window.convertPoint(toScreen: top)
        return [Double(screen.x), Double(screen.y), Double(window.frame.maxY)]
    }
    private func applyFinalState() {
        for (i, page) in pages.enumerated() {
            page.alphaValue = i == selectedIndex ? 1 : 0
            page.isHidden = i != selectedIndex
            page.setAccessibilityHidden(i != selectedIndex)
        }
        host.activePage = pages[selectedIndex]
    }
    func settle() {
        precondition(Thread.isMainThread)
        generation &+= 1; completion = nil; isAnimating = false
        animator.cancel()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        applyFinalState()
        CATransaction.commit()
    }
}
