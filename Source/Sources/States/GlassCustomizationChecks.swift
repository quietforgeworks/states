import AppKit
import StatesCore

enum GlassCustomizationChecks {
    static func run() throws {
        let suite = "local.states.glass-check.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = StatesPreferences(defaults: defaults)
        precondition(prefs.glassAppearance.isStandard)
        precondition(defaults.persistentDomain(forName: suite)?["glassStrength"] == nil)
        let material = PersonalizedGlassSurface(frame: NSRect(x: 0, y: 0, width: 300, height: 160))
        let body = FlippedView(frame: material.bounds), text = label("内容保持清晰")
        body.addSubview(text); material.contentView = body
        precondition(material.usesNativeContentHierarchy && material.regular.contentView === body)
        precondition(material.regular.style == .regular && material.regular.alphaValue == 1 && material.regular.tintColor == nil)
        prefs.menuMetric = "codex"; prefs.accent = "purple"
        prefs.glassStrength = 175; prefs.glassTransparency = 80
        prefs.glassColorMode = "custom"; prefs.glassTintHex = "#5078E0"
        let restored = StatesPreferences(defaults: UserDefaults(suiteName: suite)!)
        precondition(restored.glassAppearance == prefs.glassAppearance)
        material.apply(restored.glassAppearance)
        precondition(material.usesNativeContentHierarchy && material.regular.contentView === body)
        precondition(body.alphaValue == 1 && text.alphaValue == 1)
        precondition(material.regular.alphaValue == 1 && abs(material.backgroundOpacity - 0.4) < 0.001)
        precondition(material.regular.tintColor != nil)
        material.apply(.init(transparency: 1))
        precondition(material.backgroundOpacity == 0 && material.regular.alphaValue == 1 && body.alphaValue == 1)
        prefs.resetGlassAppearance(); material.apply(prefs.glassAppearance)
        precondition(prefs.glassAppearance.isStandard && prefs.menuMetric == "codex" && prefs.accent == "purple")
        precondition(material.usesNativeContentHierarchy && material.regular.contentView === body)
        precondition(material.regular.alphaValue == 1 && material.regular.tintColor == nil)
        print("Glass defaults, persistence, transparency, content visibility, and reset checks passed.")
    }
}
