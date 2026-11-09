import AppKit
import QuartzCore
import StatesCore

final class FlippedView: NSView { override var isFlipped: Bool { true } }
class Surface: NSView {
    override var isFlipped: Bool { true }
    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true; layer?.cornerRadius = 13; layer?.masksToBounds = true; layerContentsRedrawPolicy = .onSetNeedsDisplay }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) { NSColor.controlBackgroundColor.setFill(); dirtyRect.fill() }
}
func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
    let view = NSTextField(labelWithString: text); view.font = .systemFont(ofSize: size, weight: weight); view.textColor = color
    view.lineBreakMode = .byTruncatingTail; return view
}
final class Sparkline: NSView {
    var values: [Double?] = [] { didSet { needsDisplay = true } }
    var color = NSColor.systemTeal { didSet { needsDisplay = true } }
    var maximum = 1.0
    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true; layerContentsRedrawPolicy = .onSetNeedsDisplay }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        guard values.count > 1 else { return }
        let path = NSBezierPath(); path.lineWidth = 1.8; path.lineJoinStyle = .round
        let width = max(1, bounds.width - 2), height = max(1, bounds.height - 5)
        var connected = false
        for (index, value) in values.enumerated() {
            guard let value, value.isFinite else { connected = false; continue }
            let point = NSPoint(x: 1 + CGFloat(index) / CGFloat(values.count - 1) * width,
                y: 2 + CGFloat(min(1, max(0, value / max(maximum, 0.01)))) * height)
            if connected { path.line(to: point) } else { path.move(to: point); connected = true }
        }
        color.setStroke(); path.stroke()
    }
}
final class MetricTile: Surface {
    let title = label("", size: 12, weight: .medium, color: .secondaryLabelColor)
    let value = label("—", size: 28, weight: .semibold)
    let detail = label("采样中", size: 11, color: .secondaryLabelColor)
    let chart = Sparkline()
    init(title: String, frame: NSRect) {
        super.init(frame: frame); self.title.stringValue = title
        setAccessibilityElement(true); setAccessibilityRole(.group); setAccessibilityLabel(title)
        value.font = .monospacedDigitSystemFont(ofSize: 28, weight: .semibold)
        for view in [self.title, value, detail, chart] { addSubview(view) }
        self.title.frame = NSRect(x: 15, y: 12, width: frame.width - 30, height: 17)
        value.frame = NSRect(x: 15, y: 33, width: frame.width - 30, height: 37)
        detail.frame = NSRect(x: 15, y: 75, width: frame.width - 30, height: 17)
        chart.frame = NSRect(x: 15, y: 100, width: frame.width - 30, height: 28)
    }
    required init?(coder: NSCoder) { fatalError() }
}
final class DetailGroup: Surface {
    private var fields: [NSTextField] = []
    private var keys: [NSTextField] = []
    init(titles: [String], frame: NSRect) {
        super.init(frame: frame)
        let rowHeight = frame.height / CGFloat(max(1, titles.count))
        for (index, title) in titles.enumerated() {
            let y = CGFloat(index) * rowHeight
            let key = label(title, size: 12, color: .secondaryLabelColor)
            key.frame = NSRect(x: 15, y: y + (rowHeight - 18) / 2, width: 185, height: 18); addSubview(key); keys.append(key)
            let value = label("—", size: 13, weight: .medium); value.alignment = .right
            value.frame = NSRect(x: 205, y: y + (rowHeight - 18) / 2, width: frame.width - 220, height: 18)
            addSubview(value); fields.append(value)
            if index > 0 { let line = NSBox(frame: NSRect(x: 15, y: y, width: frame.width - 30, height: 1)); line.boxType = .separator; addSubview(line) }
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    func setTitle(_ title: String, at index: Int) { if keys.indices.contains(index) { keys[index].stringValue = title } }
    func set(_ values: [String]) { for (field, value) in zip(fields, values) { if field.stringValue != value { field.stringValue = value }; field.toolTip = value } }
}
final class DashboardController: NSViewController {
    private weak var owner: StatesAppDelegate?
    private let content = FlippedView(), overview = FlippedView(), power = FlippedView()
    private let glass = PersonalizedGlassSurface(frame: .zero)
    private let pageHost = PageTransitionHost()
    private var pageTransition: PageTransitionController?
    private var pendingUpdate = false
    var targetContentSize: NSSize { NSSize(width: 560, height: [655.0, 496][max(0, tabs.selectedSegment)]) }
    private let timestamp = label("读取中", size: 11, color: .secondaryLabelColor)
    private let tabs = GlassSegmentControl(labels: ["概览", "电源"])
    private var tiles: [MetricTile] = []
    let codexTile = CodexUsageTile(frame: NSRect(x: 286, y: 151, width: 258, height: 139))
    private var overviewIO: DetailGroup!, overviewThermal: DetailGroup!, powerDetails: DetailGroup!
    private let powerFlow = PowerFlowView()
    init(owner: StatesAppDelegate) { self.owner = owner; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }
    override func loadView() {
        let root = FlippedView(frame: NSRect(x: 0, y: 0, width: 560, height: 655))
        glass.frame = root.bounds; glass.cornerRadius = 20; glass.autoresizingMask = [.width, .height]
        content.frame = root.bounds; content.autoresizingMask = [.width, .height]; glass.contentView = content; root.addSubview(glass); view = root
        timestamp.frame = NSRect(x: 20, y: 19, width: 450, height: 18); content.addSubview(timestamp)
        let settings = NSButton(image: NSImage(systemSymbolName: "gearshape", accessibilityDescription: "设置")!, target: self, action: #selector(showSettings))
        settings.bezelStyle = .accessoryBarAction; settings.isBordered = false; settings.frame = NSRect(x: 504, y: 14, width: 34, height: 30); content.addSubview(settings)
        tabs.frame = NSRect(x: 16, y: 46, width: 528, height: 34); tabs.selectedSegment = 0; tabs.target = self; tabs.action = #selector(tabChanged); content.addSubview(tabs)
        pageHost.frame = NSRect(x: 0, y: 92, width: 560, height: 563)
        pageHost.autoresizingMask = [.width, .height]; content.addSubview(pageHost)
        for page in [overview, power] { page.frame = NSRect(x: 0, y: 0, width: 560, height: 590); pageHost.addSubview(page) }
        for (index, title) in ["CPU", "GPU", "内存"].enumerated() {
            let tile = MetricTile(title: title, frame: NSRect(x: index % 2 == 0 ? 16 : 286, y: index < 2 ? 0 : 151, width: 258, height: 139))
            overview.addSubview(tile); tiles.append(tile)
        }
        overview.addSubview(codexTile)
        overviewIO = DetailGroup(titles: ["网络下载 / 上传", "磁盘可用", "交换内存 / 压缩内存"], frame: NSRect(x: 16, y: 302, width: 528, height: 103)); overview.addSubview(overviewIO)
        overviewThermal = DetailGroup(titles: ["最高温区", "风扇转速", "系统热状态", "已运行"], frame: NSRect(x: 16, y: 417, width: 528, height: 130)); overview.addSubview(overviewThermal)
        powerFlow.frame = NSRect(x: 16, y: 0, width: 528, height: 240); power.addSubview(powerFlow)
        powerDetails = DetailGroup(titles: ["电池电量", "适配器额定功率", "电池电压 / 电流", "充放电循环"], frame: NSRect(x: 16, y: 252, width: 528, height: 136)); power.addSubview(powerDetails)
        pageTransition = PageTransitionController(host: pageHost, pages: [overview, power])
        tabChanged(); update()
    }
    @objc private func tabChanged() {
        if pageTransition?.isAnimating == true && pageTransition?.selectedIndex == tabs.selectedSegment { return }
        let animated = owner?.isDashboardVisible == true
        // Populate the destination before it becomes visible. Telemetry arriving
        // during the blend is coalesced until the current transition finishes.
        update(force: true)
        if animated { owner?.beginDashboardTransition() }
        let startHeight = owner?.dashboardHeight ?? targetContentSize.height
        let targetHeight = targetContentSize.height
        pageTransition?.transition(to: tabs.selectedSegment, animated: animated, alongside: { [weak self] progress in
            self?.owner?.resizeDashboard(height: startHeight + (targetHeight - startHeight) * progress, animated: false)
        }) { [weak self] in
            guard let self else { return }
            self.owner?.endDashboardTransition()
            self.pendingUpdate = false; self.update()
        }
    }
    func finishTransition() {
        pageTransition?.settle()
        owner?.endDashboardTransition()
        tabs.selectedSegment = tabs.selectedSegment
        if pendingUpdate { pendingUpdate = false; update() }
    }
    func update(force: Bool = false) {
        guard isViewLoaded, let owner else { return }
        if !force, pageTransition?.isAnimating == true { pendingUpdate = true; return }
        let reading = owner.engine.reading, smc = owner.engine.smc, p = reading.power
        view.appearance = owner.preferences.nativeAppearance
        glass.apply(owner.preferences.glassAppearance); tabs.applyGlassAppearance(owner.preferences.glassAppearance)
        timestamp.stringValue = owner.isPaused ? "采样已暂停" : "\(DateFormatter.localizedString(from: reading.date, dateStyle: .none, timeStyle: .medium)) 更新"
        if tabs.selectedSegment == 0 {
            tiles[0].value.stringValue = DisplayFormat.percent(reading.cpu.usage); tiles[0].detail.stringValue = reading.cpu.modelName + " · \(reading.cpu.logicalCores) 核"
            tiles[1].value.stringValue = DisplayFormat.percent(reading.gpu.usage); tiles[1].detail.stringValue = reading.gpu.usage == nil ? "读数不可用" : reading.gpu.name + (reading.gpu.coreCount.map { " · \($0) 核" } ?? "")
            tiles[2].value.stringValue = reading.memory.available ? DisplayFormat.percent(reading.memory.fraction) : "—"
            tiles[2].detail.stringValue = reading.memory.available ? "\(DisplayFormat.bytes(reading.memory.used)) / \(DisplayFormat.bytes(reading.memory.total)) · 压力\(reading.memory.pressure)" : "内存读数不可用"
            updateCodexUsage()
            let histories: [[Double?]] = [owner.engine.history.map(\.cpu), owner.engine.history.map(\.gpu), owner.engine.history.map { $0.memory }, owner.engine.history.map(\.watts)]
            for (index, tile) in tiles.enumerated() { tile.setAccessibilityValue(tile.value.stringValue + " · " + tile.detail.stringValue); tile.chart.color = owner.preferences.color; tile.chart.maximum = index == 3 ? max(40, (histories[index].compactMap { $0 }.max() ?? 0) * 1.15) : 1; tile.chart.values = histories[index] }
            overviewIO.set(["↓ \(DisplayFormat.rate(reading.network.receivedPerSecond))    ↑ \(DisplayFormat.rate(reading.network.sentPerSecond))", reading.disk.total > 0 ? "\(DisplayFormat.diskBytes(reading.disk.available)) / \(DisplayFormat.diskBytes(reading.disk.total))" : "不可用", "\(reading.memory.swapAvailable ? DisplayFormat.bytes(reading.memory.swapUsed) : "不可用") / \(reading.memory.available ? DisplayFormat.bytes(reading.memory.compressed) : "不可用")"])
            overviewThermal.set([smc.temperatures.map(\.celsius).max().map { String(format: "%.1f °C", $0) } ?? "不可用", smc.fans.isEmpty ? "不可用" : smc.fans.map { $0.currentRPM.map { "\(Int($0.rounded())) RPM" } ?? "—" }.joined(separator: " / "), reading.thermal, "\(Int(reading.uptime) / 3600) 小时 \(Int(reading.uptime) % 3600 / 60) 分钟"])
        }
        if tabs.selectedSegment == 1 {
            let telemetry = p.source == "电源适配器" ? p.systemLoadWatts : nil
            powerFlow.update(power: p, systemWatts: telemetry ?? smc.systemWatts, color: .systemBlue, systemIsEstimate: telemetry == nil)
            powerDetails.set([p.batteryPercent.map { "\(Int($0.rounded()))% · \(p.state)" } ?? p.state,
                              p.externalConnected == false ? "未连接" : DisplayFormat.watts(p.adapterRatedWatts),
                              p.voltage.flatMap { v in p.currentAmps.map { String(format: "%.2f V / %+.2f A", v, $0) } } ?? "—",
                              p.cycleCount.map { "\($0) 次" } ?? "—"])
        }
    }
    func updateCodexUsage() {
        guard isViewLoaded, let owner else { return }
        codexTile.update(owner.codexUsage, color: owner.preferences.color)
    }
    @objc private func showSettings() { owner?.showSettings() }
}
