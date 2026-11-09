import Foundation

public struct GlassAppearance: Equatable {
    public let strength: Double
    public let transparency: Double
    public let tintHex: String?
    public static let standard = GlassAppearance()
    public init(strength: Double = 1, transparency: Double = 0.5, tintHex: String? = nil) {
        self.strength = strength.isFinite ? min(2, max(0, strength)) : 1
        self.transparency = transparency.isFinite ? min(1, max(0, transparency)) : 0.5
        if let tintHex, tintHex.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil {
            self.tintHex = tintHex.uppercased()
        } else { self.tintHex = nil }
    }
    public var hasNativeGeometry: Bool { strength == 1 && transparency == 0.5 }
    public var isStandard: Bool { self == .standard }
    public var materialOpacity: Double { transparency <= 0.5 ? 1 : 2 * (1 - transparency) }
    public var regularOpacity: Double { min(1, strength) * materialOpacity }
    public var clearOpacity: Double { (1 - min(1, strength)) * materialOpacity }
    public var opaqueBacking: Double { max(0, 1 - 2 * transparency) }
    public var reinforcement: Double { max(0, strength - 1) * 0.24 * materialOpacity }
}
