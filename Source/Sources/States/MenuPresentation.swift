import AppKit
import StatesCore

enum MenuPresentation {
    static let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
    static func width(for metric: String) -> CGFloat {
        let text = caption(metric: metric, system: .init(), smc: .init())
        return ceil(NSAttributedString(string: text, attributes: [.font: font]).size().width + 12)
    }
    private static func percent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return " --%" }
        return String(format: "%3.0f%%", min(100, max(0, value * 100)))
    }
    static func caption(metric: String, system: SystemReading, smc: SMCReading, codexRemaining: Double? = nil) -> String {
        switch metric {
        case "cpu": return "C" + percent(system.cpu.usage)
        case "gpu": return "G" + percent(system.gpu.usage)
        case "memory": return "M" + percent(system.memory.available ? system.memory.fraction : nil)
        case "battery": return "B" + percent(system.power.batteryPercent.map { $0 / 100 })
        case "codex": return "Codex" + percent(codexRemaining.map { $0 / 100 })
        case "power":
            guard let watts = smc.systemWatts, watts.isFinite, watts >= 0, watts < 1000 else { return "P --.-W" }
            return String(format: "P%5.1fW", watts)
        default: return "C" + percent(system.cpu.usage) + " M" + percent(system.memory.available ? system.memory.fraction : nil)
        }
    }
    static func checkStableWidth() throws {
        struct Failure: Error {}
        for metric in ["compact", "cpu", "gpu", "memory", "battery", "power", "codex"] {
            var widths: [CGFloat] = []
            for value in [0.0, 0.01, 0.09, 0.1, 0.99, 1] {
                let reading = SystemReading(cpu: .init(usage: value), gpu: .init(usage: value), memory: .init(total: 100, used: UInt64(value * 100), available: true), power: .init(batteryPercent: value * 100))
                let caption = caption(metric: metric, system: reading, smc: .init(systemWatts: value * 999), codexRemaining: value * 100)
                widths.append(NSAttributedString(string: caption, attributes: [.font: font]).size().width)
            }
            guard let first = widths.first, widths.allSatisfy({ abs($0 - first) < 0.01 }) else { throw Failure() }
            guard widths.allSatisfy({ $0 + 12 <= width(for: metric) }) else { throw Failure() }
        }
        guard caption(metric: "codex", system: .init(), smc: .init(), codexRemaining: 92) == "Codex 92%",
              caption(metric: "codex", system: .init(), smc: .init()) == "Codex --%" else { throw Failure() }
    }
}
