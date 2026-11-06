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
        owner.engine.start()
        RunLoop.main.run(until: Date().addingTimeInterval(2.5))
        defer { owner.engine.stop() }
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
        }
        let settings = StatesSettingsController(owner: owner)
        try render(settings.window!.contentView!, "settings")
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
