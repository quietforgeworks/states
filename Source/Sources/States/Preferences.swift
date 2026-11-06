import AppKit

final class StatesPreferences {
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: ["sampleInterval": 2.0, "batterySaver": true, "menuMetric": "compact", "appearance": "system", "accent": "teal"])
    }
    var interval: Double { get { let v = defaults.double(forKey: "sampleInterval"); return [1.0, 2, 5].contains(v) ? v : 2 } set { defaults.set(newValue, forKey: "sampleInterval") } }
    var batterySaver: Bool { get { defaults.bool(forKey: "batterySaver") } set { defaults.set(newValue, forKey: "batterySaver") } }
    var menuMetric: String { get { defaults.string(forKey: "menuMetric") ?? "compact" } set { defaults.set(newValue, forKey: "menuMetric") } }
    var appearance: String { get { defaults.string(forKey: "appearance") ?? "system" } set { defaults.set(newValue, forKey: "appearance") } }
    var accent: String { get { defaults.string(forKey: "accent") ?? "teal" } set { defaults.set(newValue, forKey: "accent") } }
    var color: NSColor { ["blue": NSColor.systemBlue, "teal": .systemTeal, "purple": .systemPurple, "orange": .systemOrange][accent] ?? .systemTeal }
    var nativeAppearance: NSAppearance? { appearance == "dark" ? NSAppearance(named: .darkAqua) : appearance == "light" ? NSAppearance(named: .aqua) : nil }
}
