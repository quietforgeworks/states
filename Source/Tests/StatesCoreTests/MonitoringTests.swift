import XCTest
@testable import StatesCore

final class MonitoringTests: XCTestCase {
    func testMetricMathAndValidation() throws { try runMetricsSelfTests() }
    func testReadOnlySMCDecoding() {
        XCTAssertEqual(SMCDevice.decode(type: "flt ", bytes: [0, 0, 32, 66]), 40)
        XCTAssertEqual(SMCDevice.decode(type: "fpe2", bytes: [0x24, 0x34]), 2317)
        XCTAssertEqual(SMCDevice.decode(type: "sp78", bytes: [0xff, 0]), -1)
        XCTAssertEqual(SMCDevice.decode(type: "ui8 ", bytes: [2]), 2)
        XCTAssertEqual(SMCDevice.decode(type: "ui16", bytes: [0x12, 0x34]), 4660)
        XCTAssertNil(SMCDevice.decode(type: "flt ", bytes: [0, 0, 192, 127]))
        XCTAssertNil(SMCDevice.decode(type: "ch8*", bytes: [1, 2, 3, 4]))
    }
}
