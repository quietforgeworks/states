import AppKit
import StatesCore

enum InterfaceChecks {
    static func run(output: URL) throws {
        let app = NSApplication.shared; app.setActivationPolicy(.prohibited)
        let suite = "local.states.interface-check.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = StatesPreferences(defaults: defaults)
        let owner = StatesAppDelegate(preferences: preferences)
        owner.engine.start(); owner.codexUsage.start()
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline && (owner.codexUsage.todayTokens == nil || owner.codexUsage.windows.isEmpty) {
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        }
        defer { owner.engine.stop(); owner.codexUsage.stop() }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        func allViews(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap(allViews) }
        func render(_ view: NSView, _ name: String) throws {
            view.layoutSubtreeIfNeeded()
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
            let text = allViews(view).compactMap { ($0 as? NSTextField)?.stringValue }.joined(separator: "\n")
            precondition(!text.contains("States") && !text.contains("Pulse") && !text.contains("额定功率不代表"))
        }
        let dashboard = DashboardController(owner: owner)
        let host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 655), styleMask: .borderless, backing: .buffered, defer: false)
        host.contentView = dashboard.view
        let tabs = allViews(dashboard.view).compactMap { $0 as? GlassSegmentControl }.first!
        for (index, name) in ["overview", "power"].enumerated() {
            tabs.selectedSegment = index; _ = tabs.sendAction(tabs.action, to: tabs.target)
            host.setContentSize(dashboard.targetContentSize); dashboard.update()
            try render(dashboard.view, name)
            if index == 0 { try render(dashboard.codexTile, "codex-live") }
        }
        let usageTile = CodexUsageTile(frame: NSRect(x: 0, y: 0, width: 258, height: 139))
        let usageHost = NSWindow(contentRect: usageTile.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        usageHost.contentView = usageTile
        for (name, remaining, tokens, stale) in [("codex-normal", 92.0, Int64(112345678), false),
                                                ("codex-low", 5.0, Int64(1500000), false),
                                                ("codex-stale", 92.0, Int64(112345678), true)] {
            let now = Date()
            usageTile.update(window: .init(remaining: remaining, resetsAt: now.addingTimeInterval(6 * 86400 + 5 * 3600 + 45 * 60 + 24)),
                             tokens: tokens, stale: stale, color: .systemOrange, now: now)
            for field in allViews(usageTile).compactMap({ $0 as? NSTextField }) {
                precondition(field.intrinsicContentSize.width <= field.frame.width + 1, "Codex label would be clipped: \(field.stringValue)")
            }
            try render(usageTile, name)
        }
        usageTile.update(window: nil, tokens: nil, stale: true, color: .systemOrange)
        try render(usageTile, "codex-unavailable")
        let settings = StatesSettingsController(owner: owner)
        let menuPicker = allViews(settings.window!.contentView!).compactMap { $0 as? NSPopUpButton }
            .first { $0.itemArray.contains { $0.representedObject as? String == "codex" } }
        precondition(menuPicker?.itemArray.contains { $0.title == "Codex 剩余额度" } == true)
        try render(settings.window!.contentView!, "settings")
        let settingsRoot = settings.window!.contentView!
        let navigation = allViews(settingsRoot).compactMap { $0 as? NSTableView }
            .first { $0.identifier?.rawValue == "states-settings-navigation" }!
        navigation.selectRowIndexes(IndexSet(integer: 2), byExtendingSelection: false)
        precondition(preferences.glassAppearance.isStandard)
        try render(settingsRoot, "personalization-default")
        func control<T: NSControl>(_ id: String, as type: T.Type) -> T {
            allViews(settingsRoot).first { $0.identifier?.rawValue == id } as! T
        }
        let strength = control("states-glass-strength", as: NSSlider.self)
        let transparency = control("states-glass-transparency", as: NSSlider.self)
        let colorMode = control("states-glass-color-mode", as: NSPopUpButton.self)
        let colorWell = control("states-glass-color", as: NSColorWell.self)
        strength.doubleValue = 160; _ = strength.sendAction(strength.action, to: strength.target)
        transparency.doubleValue = 75; _ = transparency.sendAction(transparency.action, to: transparency.target)
        colorMode.selectItem(at: 1); _ = colorMode.sendAction(colorMode.action, to: colorMode.target)
        colorWell.color = NSColor(srgbRed: 0.35, green: 0.3, blue: 0.85, alpha: 1)
        _ = colorWell.sendAction(colorWell.action, to: colorWell.target)
        precondition(preferences.glassStrength == 160 && preferences.glassTransparency == 75 && preferences.glassColorMode == "custom")
        try render(settingsRoot, "personalization-custom")
        tabs.selectedSegment = 0; _ = tabs.sendAction(tabs.action, to: tabs.target)
        host.setContentSize(dashboard.targetContentSize); dashboard.update()
        try render(dashboard.view, "overview-custom-glass")
        let reset = control("states-reset-glass", as: NSButton.self); reset.performClick(nil)
        precondition(preferences.glassAppearance.isStandard)
        dashboard.update(); try render(dashboard.view, "overview-reset-glass")
        try render(settingsRoot, "personalization-reset")
        let flow = PowerFlowView(frame: NSRect(x: 0, y: 0, width: 528, height: 240))
        let flowHost = NSWindow(contentRect: flow.bounds, styleMask: .borderless, backing: .buffered, defer: false); flowHost.contentView = flow
        let cases: [(String, StatesCore.PowerReading, Double?)] = [
            ("flow-charging", .init(source: "电源适配器", state: "充电中", batteryPercent: 72, batteryWatts: 6.47, adapterRatedWatts: 94, inputWatts: 64.81), 58.34),
            ("flow-battery", .init(source: "电池", state: "放电中", batteryPercent: 63, batteryWatts: -18.5), 17.2),
            ("flow-battery-stale-zero", .init(source: "电池", state: "放电中", batteryPercent: 99, batteryWatts: 0), 10.33),
            ("flow-battery-missing", .init(source: "电池", state: "放电中", batteryPercent: 50), nil),
            ("flow-combined", .init(source: "电源适配器", state: "电池辅助", batteryPercent: 45, batteryWatts: -8, inputWatts: 20), 28),
            ("flow-idle", .init(source: "电源适配器", state: "已充满", batteryPercent: 100, batteryWatts: 0, inputWatts: 12), 12),
            ("flow-unavailable", .init(), nil)
        ]
        for (name, reading, watts) in cases {
            flow.update(power: reading, systemWatts: watts, color: .systemBlue, systemIsEstimate: false)
            try render(flow, name)
            if name == "flow-battery-stale-zero" {
                let values = allViews(flow).compactMap { ($0 as? NSTextField)?.stringValue }
                precondition(values.contains("≈10.33 W") && !values.contains("0.00 W"))
            }
        }
        try MenuPresentation.checkStableWidth()
        print("Interface checks passed; cores=\(owner.engine.reading.cpu.cores.count), temperatures=\(owner.engine.smc.temperatures.count), menu widths stable.")
    }
}
