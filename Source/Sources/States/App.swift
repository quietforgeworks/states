import AppKit
import QuartzCore
import ServiceManagement
import UniformTypeIdentifiers
import StatesCore

@main enum StatesApplication {
    static func main() {
        if let index = CommandLine.arguments.firstIndex(of: "--check-interface"), CommandLine.arguments.count > index + 1 {
            do { try InterfaceChecks.run(output: URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)); return }
            catch { fputs("Interface check failed: \(error)\n", stderr); exit(1) }
        }
        if CommandLine.arguments.contains("--self-test") {
            do { try runMetricsSelfTests(); try MenuPresentation.checkStableWidth(); try MotionChecks.run(); print("States self-tests passed."); return }
            catch { fputs("States self-test failed: \(error)\n", stderr); exit(1) }
        }
        if CommandLine.arguments.contains("--probe") {
            let sampler = NativeMetricsSampler(); _ = sampler.sample()
            Thread.sleep(forTimeInterval: 0.25)
            struct Probe: Encodable { var system: SystemReading; var smc: SMCReading }
            let result = Probe(system: sampler.sample(), smc: SMCDevice().snapshot())
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(result) { FileHandle.standardOutput.write(data); print("") }
            return
        }
        let app = NSApplication.shared; app.setActivationPolicy(.accessory)
        let delegate = StatesAppDelegate(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class StatesAppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let preferences: StatesPreferences
    init(preferences: StatesPreferences = StatesPreferences()) { self.preferences = preferences; super.init() }
    lazy var engine = MonitorEngine(prefs: preferences)
    let awake = AwakeController()
    private var item: NSStatusItem!
    private let popover = NSPopover()
    private var transitionAnchor: NSPoint?
    private var dashboard: DashboardController!
    private var settings: StatesSettingsController?
    private var workspaceTokens: [NSObjectProtocol] = []
    private(set) var isPaused = false
    var isDashboardVisible: Bool { popover.isShown }
    var dashboardHeight: CGFloat { popover.contentSize.height }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let main = NSMenu(), application = NSMenuItem(), appMenu = NSMenu()
        let settingsItem = NSMenuItem(title: "设置…", action: #selector(showSettings), keyEquivalent: ","); settingsItem.target = self; appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        application.submenu = appMenu; main.addItem(application); NSApp.mainMenu = main
        item = NSStatusBar.system.statusItem(withLength: MenuPresentation.width(for: preferences.menuMetric))
        item.button?.image = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: "系统状态")
        item.button?.image?.size = NSSize(width: 16, height: 16)
        item.button?.image?.isTemplate = true; item.button?.imagePosition = .imageLeading
        item.button?.target = self; item.button?.action = #selector(statusClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        dashboard = DashboardController(owner: self); popover.contentViewController = dashboard
        popover.contentSize = NSSize(width: 560, height: 655); popover.behavior = .transient; popover.animates = true; popover.delegate = self
        engine.onUpdate = { [weak self] in self?.update() }
        awake.onChange = { [weak self] in if self?.settings?.window?.isVisible == true { self?.settings?.refreshState() } }
        let center = NSWorkspace.shared.notificationCenter
        workspaceTokens.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.engine.stop(); self?.popover.performClose(nil)
        })
        workspaceTokens.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }; if !self.isPaused { self.engine.start() }
        })
        engine.start(); update()
        if CommandLine.arguments.contains("--show-settings") { DispatchQueue.main.async { self.showSettings() } }
        else if !preferences.defaults.bool(forKey: "hasLaunched") || CommandLine.arguments.contains("--show") {
            preferences.defaults.set(true, forKey: "hasLaunched")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.showDashboard() }
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showDashboard(); return true }
    func applicationDidBecomeActive(_ notification: Notification) { settings?.refreshState() }
    func applicationWillTerminate(_ notification: Notification) {
        engine.stop(); awake.disable()
        for token in workspaceTokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
    }
    func popoverDidShow(_ notification: Notification) { dashboard.update() }
    func popoverDidClose(_ notification: Notification) {
        guard !popover.isShown else { return }
        dashboard.finishTransition()
        let target = dashboard.targetContentSize
        popover.animates = false; popover.contentSize = target
        dashboard.view.setFrameSize(target)
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp { showMenu() }
        else if popover.isShown { popover.performClose(nil) } else { showDashboard() }
    }
    func showDashboard() {
        guard let button = item?.button else { return }
        if !popover.isShown {
            dashboard.finishTransition()
            resizeDashboard(height: dashboard.targetContentSize.height, animated: false)
            dashboard.view.setFrameSize(dashboard.targetContentSize)
        }
        popover.appearance = preferences.nativeAppearance
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.title = "系统监控"
        popover.contentViewController?.view.window?.makeKey()
        dashboard.update()
    }
    func beginDashboardTransition() {
        if transitionAnchor == nil, let frame = dashboard?.view.window?.frame {
            transitionAnchor = NSPoint(x: frame.minX, y: frame.maxY)
        }
        popover.animates = false
    }
    func endDashboardTransition() {
        transitionAnchor = nil
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
    func resizeDashboard(height: CGFloat, animated: Bool = true) {
        // Page blending and resizing share the page animator's display tick.
        // Integral view coordinates keep AppKit's popover layout from alternating
        // between fractional content heights and rounded window heights.
        let value = height.rounded()
        guard abs(popover.contentSize.height - value) > 0.01 else { return }
        let saved = popover.animates
        popover.animates = false
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        NSAnimationContext.current.allowsImplicitAnimation = false
        CATransaction.begin(); CATransaction.setDisableActions(true)
        popover.contentSize = NSSize(width: 560, height: value)
        dashboard?.view.layoutSubtreeIfNeeded()
        if let anchor = transitionAnchor, let window = dashboard?.view.window {
            let origin = NSPoint(x: anchor.x, y: anchor.y - window.frame.height)
            if window.frame.origin != origin { window.setFrameOrigin(origin) }
        }
        CATransaction.commit(); NSAnimationContext.endGrouping()
        popover.animates = saved
    }
    @objc func showSettings() {
        if settings == nil { settings = StatesSettingsController(owner: self) }
        settings?.prepareForPresentation(); settings?.refreshState()
        guard let window = settings?.window else { return }
        let fade = !window.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        window.animationBehavior = .none
        if fade { window.alphaValue = 0 }
        popover.performClose(nil)
        NSApp.activate(ignoringOtherApps: true)
        settings?.showWindow(nil); window.makeKeyAndOrderFront(nil)
        if fade {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                window.animator().alphaValue = 1
            } completionHandler: { [weak window] in
                window?.animationBehavior = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? .none : .default
            }
        } else {
            window.alphaValue = 1
            window.animationBehavior = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? .none : .default
        }
    }
    private func update() {
        let sample = engine.reading
        let text = " " + MenuPresentation.caption(metric: preferences.menuMetric, system: sample, smc: engine.smc)
        let width = MenuPresentation.width(for: preferences.menuMetric)
        if item?.length != width { item?.length = width }
        if item?.button?.attributedTitle.string != text {
            item?.button?.attributedTitle = NSAttributedString(string: text, attributes: [.font: MenuPresentation.font])
        }
        item?.button?.toolTip = "CPU \(DisplayFormat.percent(sample.cpu.usage)) · GPU \(DisplayFormat.percent(sample.gpu.usage)) · 内存 \(DisplayFormat.bytes(sample.memory.used))"
        if popover.isShown { dashboard.update() }
    }
    func preferencesChanged() {
        if !isPaused { engine.start() }
        popover.appearance = preferences.nativeAppearance; dashboard?.view.appearance = preferences.nativeAppearance
        update(); settings?.refreshState()
    }
    func setLoginEnabled(_ enabled: Bool) {
        do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
        catch { alert("无法更改登录启动", error.localizedDescription) }
        settings?.refreshState()
    }
    @objc private func togglePause() { isPaused.toggle(); if isPaused { engine.stop() } else { engine.start() }; update(); dashboard.update() }
    @objc func exportSnapshot() {
        popover.performClose(nil)
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "系统状态.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        struct Report: Encodable { let system: SystemReading; let smc: SMCReading }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(Report(system: engine.reading, smc: engine.smc)).write(to: url, options: .atomic)
        } catch { alert("无法导出", error.localizedDescription) }
    }
    private func showMenu() {
        let menu = NSMenu()
        func entry(_ title: String, _ action: Selector) { let i = NSMenuItem(title: title, action: action, keyEquivalent: ""); i.target = self; menu.addItem(i) }
        entry("设置…", #selector(showSettings)); entry(isPaused ? "继续采样" : "暂停采样", #selector(togglePause)); entry("导出当前状态…", #selector(exportSnapshot))
        menu.addItem(.separator()); let quit = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"); menu.addItem(quit)
        if let button = item.button { menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY), in: button) }
    }
    private func alert(_ title: String, _ message: String) { let a = NSAlert(); a.messageText = title; a.informativeText = message; a.runModal() }
}
