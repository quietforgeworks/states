import AppKit
import QuartzCore
import StatesCore

/// A qualitative flow diagram. Each number is its own measured channel;
/// band widths never calculate or imply a conserved system power total.
final class PowerFlowView: NSView {
    override var isFlipped: Bool { true }

    private enum Topology { case split, battery, combined }
    private var power = PowerReading()
    private var systemWatts: Double?
    private var accent = NSColor.systemBlue
    private var topology = Topology.split
    private var hasReading = false
    private var lastSize: NSSize?
    private var systemIsEstimate = true
    private let bands = [CAShapeLayer(), CAShapeLayer()]
    private let nodes = [PowerFlowNode(), PowerFlowNode(), PowerFlowNode()]
    private let values = [PowerFlowView.valueLabel(), PowerFlowView.valueLabel()]
    private let directions = [PowerFlowView.directionLabel(), PowerFlowView.directionLabel()]

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 20
        layer?.masksToBounds = true
        for band in bands { layer?.addSublayer(band) }
        for node in nodes { addSubview(node) }
        for value in values { addSubview(value) }
        for direction in directions { addSubview(direction) }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("功率流")
        render(animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(power: PowerReading, systemWatts: Double?, color: NSColor, systemIsEstimate: Bool = true) {
        guard !hasReading || self.power != power || self.systemWatts != systemWatts || self.accent != color || self.systemIsEstimate != systemIsEstimate else { return }
        self.systemIsEstimate = systemIsEstimate
        let previous = topology
        self.power = power
        self.systemWatts = valid(systemWatts)
        accent = color
        if power.externalConnected == false || power.source == "电池" {
            topology = .battery
        } else if let watts = valid(power.batteryWatts), watts < 0 {
            topology = .combined
        } else {
            topology = .split
        }
        if hasReading && previous != topology && window?.isVisible == true && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let fade = CATransition(); fade.type = .fade; fade.duration = 0.22
            layer?.add(fade, forKey: "flowTopology")
        }
        render(animated: hasReading && previous == topology)
        hasReading = true
    }

    override func layout() {
        super.layout()
        guard lastSize != bounds.size else { return }
        lastSize = bounds.size
        render(animated: false)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        render(animated: false)
    }

    private func valid(_ value: Double?) -> Double? {
        value.flatMap { $0.isFinite ? $0 : nil }
    }

    private func watts(_ value: Double?) -> String {
        guard let value = valid(value) else { return "—" }
        return String(format: "%.2f W", abs(value))
    }

    private func thickness(_ value: Double?, maximum: Double, limit: CGFloat) -> CGFloat {
        guard let value = valid(value) else { return 4 }
        guard abs(value) > 0 else { return 2 }
        return 8 + (limit - 8) * CGFloat(sqrt(min(1, abs(value) / maximum)))
    }

    private func render(animated: Bool) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let scaleX = bounds.width / 528, scaleY = bounds.height / 240
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
            NSRect(x: x * scaleX, y: y * scaleY, width: w * scaleX, height: h * scaleY)
        }
        let input = valid(power.inputWatts).flatMap { $0 >= 0 ? $0 : nil }
        let rawBattery = valid(power.batteryWatts)
        let measuredBattery = topology == .battery ? rawBattery.flatMap { $0 < -0.01 ? $0 : nil } : rawBattery
        let system = systemWatts.flatMap { $0 >= 0 ? $0 : nil }
        // On battery, missing/stale current is not a measured zero. A clearly
        // marked system-load estimate keeps the supply flow meaningful.
        let batteryEstimated = topology == .battery && measuredBattery == nil && (system ?? 0) > 0.05
        let battery = measuredBattery ?? (batteryEstimated ? system.map { -$0 } : nil)
        let batteryText = (batteryEstimated ? "≈" : "") + watts(battery)
        let maximum = max(1, abs(battery ?? 0), system ?? 0, input ?? 0)
        let systemText = (systemIsEstimate && system != nil ? "≈" : "") + watts(system)
        let percentage = min(100, max(0, power.batteryPercent ?? 100))
        let batterySymbol = "battery.\(Int((percentage / 25).rounded()) * 25)percent"
        let green = NSColor.systemGreen
        let blue = accent
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let animate = animated && window != nil && !reduceMotion
        effectiveAppearance.performAsCurrentDrawingAppearance {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.85).cgColor
            CATransaction.commit()
        }
        for index in nodes.indices { nodes[index].isHidden = false }
        for index in values.indices { values[index].isHidden = false; directions[index].isHidden = true }

        switch topology {
        case .split:
            nodes[0].frame = rect(16, 42, 76, 180)
            nodes[1].frame = rect(436, 18, 76, 76)
            nodes[2].frame = rect(436, 116, 76, 106)
            nodes[0].configure(symbol: "bolt.fill", title: "电源", value: watts(input), color: .labelColor)
            nodes[1].configure(symbol: battery.map { $0 > 0 } == true ? "battery.100percent.bolt" : batterySymbol, title: "电池", value: nil, color: green)
            nodes[2].configure(symbol: "laptopcomputer", title: "电脑", value: nil, color: blue)
            let batteryWidth = thickness(battery, maximum: maximum, limit: 54)
            let systemWidth = thickness(system, maximum: maximum, limit: 100)
            applyBand(0, start: CGPoint(x: 100, y: 88), end: CGPoint(x: 428, y: 56), width: batteryWidth,
                      color: green, measured: battery, animated: animate)
            applyBand(1, start: CGPoint(x: 100, y: 164), end: CGPoint(x: 428, y: 169), width: systemWidth,
                      color: blue, measured: system, animated: animate)
            positionValue(0, text: batteryText, direction: battery == nil || battery == 0 ? "" : "›", frame: rect(194, 59, 140, 26), color: green)
            positionValue(1, text: systemText, direction: system == nil || system == 0 ? "" : "›", frame: rect(194, 153, 140, 26), color: blue)
        case .battery:
            nodes[0].frame = rect(16, 54, 84, 132)
            nodes[1].isHidden = true
            nodes[2].frame = rect(428, 54, 84, 132)
            nodes[0].configure(symbol: batterySymbol, title: "电池", value: batteryText, color: green)
            nodes[2].configure(symbol: "laptopcomputer", title: "电脑", value: systemText, color: blue)
            let width = thickness(battery, maximum: maximum, limit: 104)
            applyBand(0, start: CGPoint(x: 108, y: 120), end: CGPoint(x: 420, y: 120), width: width,
                      color: green, measured: battery, animated: animate)
            hideBand(1)
            positionValue(0, text: batteryText, direction: battery == nil || battery == 0 ? "" : "›", frame: rect(196, 107, 140, 26), color: green)
            values[1].isHidden = true; directions[1].isHidden = true
        case .combined:
            nodes[0].frame = rect(16, 18, 84, 88)
            nodes[1].frame = rect(16, 134, 84, 88)
            nodes[2].frame = rect(428, 54, 84, 132)
            nodes[0].configure(symbol: "bolt.fill", title: "电源", value: watts(input), color: .labelColor)
            nodes[1].configure(symbol: batterySymbol, title: "电池", value: batteryText, color: green)
            nodes[2].configure(symbol: "laptopcomputer", title: "电脑", value: systemText, color: blue)
            applyBand(0, start: CGPoint(x: 108, y: 62), end: CGPoint(x: 420, y: 94),
                      width: thickness(input, maximum: maximum, limit: 54), color: blue, measured: input, animated: animate)
            applyBand(1, start: CGPoint(x: 108, y: 178), end: CGPoint(x: 420, y: 154),
                      width: thickness(battery, maximum: maximum, limit: 54), color: green, measured: battery, animated: animate)
            positionValue(0, text: watts(input), direction: input == nil || input == 0 ? "" : "›", frame: rect(200, 62, 140, 26), color: blue)
            positionValue(1, text: batteryText, direction: battery == nil || battery == 0 ? "" : "›", frame: rect(200, 155, 140, 26), color: green)
        }
        let direction = topology == .battery ? "电池供电" : topology == .combined ? "电源与电池共同供电" : "电源供电"
        setAccessibilityValue("\(direction)，输入 \(watts(input))，电池 \(batteryText)，电脑 \(systemText)")
    }

    private func applyBand(_ index: Int, start: CGPoint, end: CGPoint, width: CGFloat,
                           color: NSColor, measured: Double?, animated: Bool) {
        let sx = bounds.width / 528, sy = bounds.height / 240
        let path = CGMutablePath()
        let half = width / 2
        let bend = (end.x - start.x) * 0.46
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * sx, y: y * sy) }
        path.move(to: point(start.x, start.y - half))
        path.addCurve(to: point(end.x, end.y - half), control1: point(start.x + bend, start.y - half), control2: point(end.x - bend, end.y - half))
        path.addLine(to: point(end.x, end.y + half))
        path.addCurve(to: point(start.x, start.y + half), control1: point(end.x - bend, end.y + half), control2: point(start.x + bend, start.y + half))
        path.closeSubpath()
        let band = bands[index]
        let previous = band.presentation()?.path ?? band.path
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        band.isHidden = false
        band.path = path
        effectiveAppearance.performAsCurrentDrawingAppearance {
            band.fillColor = color.withAlphaComponent(measured == nil ? 0.055 : measured == 0 ? 0.08 : 0.18).cgColor
        }
        CATransaction.commit()
        if animated, let previous {
            let animation = CABasicAnimation(keyPath: "path")
            animation.fromValue = previous; animation.toValue = path
            animation.duration = 0.35
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            band.add(animation, forKey: "flowWidth")
        } else { band.removeAnimation(forKey: "flowWidth") }
    }

    private func hideBand(_ index: Int) {
        bands[index].removeAllAnimations()
        bands[index].isHidden = true
    }

    private func positionValue(_ index: Int, text: String, direction: String, frame: NSRect, color: NSColor) {
        values[index].frame = frame
        values[index].stringValue = text
        directions[index].frame = NSRect(x: frame.maxX - 8, y: frame.minY, width: 20, height: frame.height)
        directions[index].stringValue = ""
        directions[index].textColor = color.withAlphaComponent(0.7)
    }

    private static func valueLabel() -> NSTextField {
        let field = NSTextField(labelWithString: "—")
        field.font = .monospacedDigitSystemFont(ofSize: 17, weight: .semibold)
        field.alignment = .center
        field.textColor = .labelColor
        return field
    }

    private static func directionLabel() -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.font = .systemFont(ofSize: 23, weight: .medium)
        field.alignment = .center
        return field
    }
}

private final class PowerFlowNode: NSView {
    override var isFlipped: Bool { true }
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let value = NSTextField(labelWithString: "")
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 19
        layer?.shadowColor = NSColor.black.cgColor; layer?.shadowOpacity = 0.08
        layer?.shadowRadius = 6; layer?.shadowOffset = NSSize(width: 0, height: -1)
        title.font = .systemFont(ofSize: 11, weight: .medium)
        title.textColor = .secondaryLabelColor
        title.alignment = .center
        value.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        value.alignment = .center
        for view in [icon, title, value] { addSubview(view) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(symbol: String, title: String, value: String?, color: NSColor) {
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 25, weight: .regular)
        icon.contentTintColor = color
        self.title.stringValue = title
        self.value.stringValue = value ?? ""
        self.value.isHidden = value == nil
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.9).cgColor
            layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.16).cgColor
            layer?.borderWidth = 0.5
        }
        needsLayout = true
    }
    override func layout() {
        super.layout()
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: 19, cornerHeight: 19, transform: nil)
        let total: CGFloat = value.isHidden ? 44 : 64
        let top = max(3, (bounds.height - total) / 2)
        icon.frame = NSRect(x: (bounds.width - 32) / 2, y: top, width: 32, height: 26)
        title.frame = NSRect(x: 2, y: top + 30, width: bounds.width - 4, height: 14)
        value.frame = NSRect(x: 2, y: top + 48, width: bounds.width - 4, height: 16)
    }
}
