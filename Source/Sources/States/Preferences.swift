import AppKit
import StatesCore

final class StatesPreferences {
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: ["sampleInterval": 2.0, "batterySaver": true, "menuMetric": "compact", "appearance": "system", "accent": "teal",
                                    "glassStrength": 100.0, "glassTransparency": 50.0, "glassColorMode": "system", "glassTintHex": "#00BACA"])
    }
    var interval: Double { get { let v = defaults.double(forKey: "sampleInterval"); return [1.0, 2, 5].contains(v) ? v : 2 } set { defaults.set(newValue, forKey: "sampleInterval") } }
    var batterySaver: Bool { get { defaults.bool(forKey: "batterySaver") } set { defaults.set(newValue, forKey: "batterySaver") } }
    var menuMetric: String { get { defaults.string(forKey: "menuMetric") ?? "compact" } set { defaults.set(newValue, forKey: "menuMetric") } }
    var appearance: String { get { defaults.string(forKey: "appearance") ?? "system" } set { defaults.set(newValue, forKey: "appearance") } }
    var accent: String { get { defaults.string(forKey: "accent") ?? "teal" } set { defaults.set(newValue, forKey: "accent") } }
    var color: NSColor { ["blue": NSColor.systemBlue, "teal": .systemTeal, "purple": .systemPurple, "orange": .systemOrange][accent] ?? .systemTeal }
    var nativeAppearance: NSAppearance? { appearance == "dark" ? NSAppearance(named: .darkAqua) : appearance == "light" ? NSAppearance(named: .aqua) : nil }
    var glassStrength: Double {
        get { let v = defaults.double(forKey: "glassStrength"); return v.isFinite ? min(200, max(0, v)) : 100 }
        set { defaults.set(newValue.isFinite ? min(200, max(0, newValue)) : 100, forKey: "glassStrength") }
    }
    var glassTransparency: Double {
        get { let v = defaults.double(forKey: "glassTransparency"); return v.isFinite ? min(100, max(0, v)) : 50 }
        set { defaults.set(newValue.isFinite ? min(100, max(0, newValue)) : 50, forKey: "glassTransparency") }
    }
    var glassColorMode: String { get { defaults.string(forKey: "glassColorMode") == "custom" ? "custom" : "system" } set { defaults.set(newValue == "custom" ? "custom" : "system", forKey: "glassColorMode") } }
    var glassTintHex: String { get { GlassAppearance(tintHex: defaults.string(forKey: "glassTintHex")).tintHex ?? "#00BACA" } set { defaults.set(GlassAppearance(tintHex: newValue).tintHex ?? "#00BACA", forKey: "glassTintHex") } }
    var glassAppearance: GlassAppearance {
        .init(strength: glassStrength / 100, transparency: glassTransparency / 100, tintHex: glassColorMode == "custom" ? glassTintHex : nil)
    }
    func resetGlassAppearance() {
        for key in ["glassStrength", "glassTransparency", "glassColorMode", "glassTintHex"] { defaults.removeObject(forKey: key) }
    }
}
