import AppKit
import QuartzCore

enum MotionChecks {
    private enum Failure: Error { case failed(String) }
    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw Failure.failed(message) }
    }
    static func run() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let root = FlippedView(frame: NSRect(x: 0, y: 0, width: 300, height: 240))
        let host = PageTransitionHost(frame: root.bounds); root.addSubview(host)
        let pages = (0..<3).map { _ in FlippedView(frame: host.bounds) }
        let buttons = pages.enumerated().map { index, page -> NSButton in
            let button = NSButton(title: "Page \(index)", target: nil, action: nil)
            button.frame = NSRect(x: 10, y: 10, width: 90, height: 28); page.addSubview(button); return button
        }
        let transition = PageTransitionController(host: host, pages: pages)
        try require(!pages[0].isHidden && pages[1].isHidden && pages[2].isHidden, "Initial page was not isolated")
        let frames = pages.map(\.frame)
        let order = host.subviews.map(ObjectIdentifier.init)
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        func advance(_ seconds: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        var stale = 0, latest = 0
        transition.transition(to: 1, animated: true, completion: { stale += 1 })
        advance(0.10)
        if !reduced {
            try require(pages[1].alphaValue > 0 && pages[1].alphaValue < 1 && pages[0].alphaValue > 0,
                        "No applied intermediate page alpha")
        }
        let applied = pages.map(\.alphaValue)
        transition.transition(to: 2, animated: true, completion: { latest += 1 })
        if !reduced { try require(pages.map(\.alphaValue) == applied, "Retarget jumped from applied view state") }
        advance(0.08)
        try require(transition.selectedIndex == 2 && stale == (reduced ? 1 : 0), "Superseded transition completed")
        try require(pages.map(\.frame) == frames, "Page transition changed content geometry")
        try require(host.subviews.map(ObjectIdentifier.init) == order, "Retarget reordered content")
        try require(host.activePage === pages[2], "Outgoing page still owns input")
        try require(host.hitTest(NSPoint(x: 25, y: 20)) === buttons[2], "Selected page does not receive input")
        advance(0.30)
        try require(latest == 1 && !transition.isAnimating && pages[2].alphaValue == 1, "Latest transition did not finish once")
        transition.transition(to: 0, animated: false)
        try require(pages[1].isHidden && pages[2].isHidden && pages[0].alphaValue == 1, "Immediate transition incomplete")
        transition.transition(to: 1, animated: true, completion: { stale += 1 })
        advance(0.05); transition.settle(); advance(0.30)
        try require(!transition.isAnimating && !pages[1].isHidden && pages[0].isHidden, "Cancelled driver changed settled pages")
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        for count in [2, 3] {
            let tabs = GlassSegmentControl(labels: Array(["概览", "电源", "控制"].prefix(count)))
            tabs.frame = NSRect(x: 0, y: 0, width: 528, height: 34); root.addSubview(tabs)
            tabs.layoutSubtreeIfNeeded()
            guard let glass = descendants(tabs).first(where: { $0.identifier?.rawValue == "states-tab-selection" }) as? NSGlassEffectView else { throw Failure.failed("Missing native selection") }
            let buttons = tabs.subviews.compactMap { $0 as? NSButton }.sorted { $0.tag < $1.tag }
            for index in [count - 1, 0, count - 1] {
                buttons[index].performClick(nil)
                advance(0.10)
                if !reduced && index != 0 {
                    try require(glass.frame.minX > 3 && glass.frame.minX < 3 + CGFloat(count - 1) * (tabs.bounds.width - 6) / CGFloat(count), "Native glass frame had no intermediate positions")
                }
                advance(0.30)
                let expected = 3 + CGFloat(index) * (tabs.bounds.width - 6) / CGFloat(count)
                try require(tabs.selectedSegment == index && abs(glass.frame.minX - expected) < 0.5, "Native glass frame did not follow selected tab")
                let before = glass.frame
                tabs.needsLayout = true; tabs.layoutSubtreeIfNeeded()
                try require(glass.frame == before, "Parent layout reset native selection")
            }
            tabs.removeFromSuperview()
        }
        print("Page motion and native selection-frame checks passed.")
    }
}
