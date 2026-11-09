import XCTest
@testable import StatesCore

final class GlassAppearanceTests: XCTestCase {
    func testDefaultsUseOriginalNativeMaterial() {
        let value = GlassAppearance()
        XCTAssertTrue(value.isStandard); XCTAssertTrue(value.hasNativeGeometry)
        XCTAssertEqual(value.regularOpacity, 1); XCTAssertEqual(value.clearOpacity, 0)
        XCTAssertEqual(value.opaqueBacking, 0); XCTAssertEqual(value.reinforcement, 0)
        XCTAssertNil(value.tintHex)
    }
    func testTransparencyEndpointsAndStrengthRemainIndependent() {
        let opaque = GlassAppearance(strength: 0.25, transparency: 0)
        XCTAssertEqual(opaque.opaqueBacking, 1); XCTAssertEqual(opaque.regularOpacity, 0.25)
        XCTAssertEqual(opaque.clearOpacity, 0.75)
        let transparent = GlassAppearance(strength: 2, transparency: 1)
        XCTAssertEqual(transparent.materialOpacity, 0); XCTAssertEqual(transparent.opaqueBacking, 0)
        XCTAssertEqual(transparent.reinforcement, 0)
        let custom = GlassAppearance(strength: 1.5, transparency: 0.75)
        XCTAssertEqual(custom.materialOpacity, 0.5); XCTAssertEqual(custom.reinforcement, 0.06, accuracy: 0.0001)
    }
    func testBoundsAndInvalidPersistedValues() {
        XCTAssertEqual(GlassAppearance(strength: -5, transparency: 10).strength, 0)
        XCTAssertEqual(GlassAppearance(strength: 5, transparency: -10).transparency, 0)
        XCTAssertTrue(GlassAppearance(strength: .nan, transparency: .infinity).isStandard)
        XCTAssertEqual(GlassAppearance(tintHex: "#1a2Bc3").tintHex, "#1A2BC3")
        XCTAssertNil(GlassAppearance(tintHex: "invalid").tintHex)
    }
}
