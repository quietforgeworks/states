import Foundation
import XCTest
@testable import StatesCore

final class BatteryTests: XCTestCase {
    private func frame(external: Bool = false, charging: Bool = false, instant: NSNumber? = nil, average: NSNumber? = nil) -> [String: Any] {
        var frame: [String: Any] = ["ExternalConnected": external, "IsCharging": charging, "Voltage": 13000]
        frame["InstantAmperage"] = instant
        frame["Amperage"] = average
        return frame
    }
    func testInstantDischargeOverridesCachedAverageZero() {
        let reading = MetricsMath.applyingBatteryRegistry(to: .init(), properties: frame(instant: -1000, average: 0))
        XCTAssertEqual(reading.batteryWatts, -13)
        XCTAssertEqual(reading.currentAmps, -1)
        XCTAssertEqual(reading.batteryPowerSource, "InstantAmperage × Voltage")
    }
    func testUnsignedCurrentEncodingsAreSignedBeforeConversion() {
        for raw in [NSNumber(value: UInt64(bitPattern: Int64(-1000))), NSNumber(value: UInt32(bitPattern: Int32(-1000)))] {
            let reading = MetricsMath.applyingBatteryRegistry(to: .init(), properties: frame(instant: raw))
            XCTAssertEqual(reading.batteryWatts, -13)
        }
    }
    func testUnavailableAndStaleCurrentsDoNotClaimZeroPowerOnBattery() {
        for current in [nil, NSNumber(value: 0), NSNumber(value: 500), NSNumber(value: 100000), NSNumber(value: Double.nan)] {
            let reading = MetricsMath.applyingBatteryRegistry(to: .init(), properties: frame(instant: current, average: 0))
            XCTAssertNil(reading.batteryWatts)
            XCTAssertNil(reading.currentAmps)
            XCTAssertNil(reading.batteryPowerSource)
        }
    }
    func testAverageDischargeFallbackAndInvalidVoltage() {
        var properties = frame(instant: 0, average: -1000)
        let reading = MetricsMath.applyingBatteryRegistry(to: .init(), properties: properties)
        XCTAssertEqual(reading.batteryWatts, -13)
        XCTAssertEqual(reading.batteryPowerSource, "Amperage × Voltage")
        properties["Voltage"] = 0
        XCTAssertNil(MetricsMath.applyingBatteryRegistry(to: .init(), properties: properties).batteryWatts)
    }
    func testChargingAndPausedExternalPower() {
        let charging = MetricsMath.applyingBatteryRegistry(to: .init(), properties: frame(external: true, charging: true, instant: 1000))
        XCTAssertEqual(charging.state, "充电中")
        XCTAssertEqual(charging.batteryWatts, 13)
        let paused = MetricsMath.applyingBatteryRegistry(to: .init(), properties: frame(external: true, instant: 0, average: 500))
        XCTAssertEqual(paused.state, "已接电 · 暂停充电")
        XCTAssertEqual(paused.batteryWatts, 0)
    }
    func testDisconnectOverridesStaleIOPSAndPurgesAdapterTelemetry() {
        let cached = PowerReading(source: "电源适配器", state: "充电中", batteryWatts: 13,
            adapterRatedWatts: 96, inputWatts: 20, systemLoadWatts: 7, remainingMinutes: 50)
        var properties = frame(instant: 0, average: 500)
        properties["AdapterDetails"] = ["Watts": 96]
        properties["PowerTelemetryData"] = ["SystemPowerIn": 20000, "SystemVoltageIn": 20000, "SystemCurrentIn": 1000, "SystemLoad": 7000]
        let reading = MetricsMath.applyingBatteryRegistry(to: cached, properties: properties)
        XCTAssertEqual(reading.source, "电池")
        XCTAssertEqual(reading.state, "放电中")
        XCTAssertEqual(reading.externalConnected, false)
        XCTAssertNil(reading.remainingMinutes)
        XCTAssertNil(reading.adapterRatedWatts)
        XCTAssertNil(reading.inputWatts)
        XCTAssertNil(reading.systemLoadWatts)
        XCTAssertNil(reading.batteryWatts)
    }
    func testIOPSBatteryFallbackRejectsZeroWhenRegistryConnectionMissing() {
        XCTAssertNil(MetricsMath.applyingBatteryRegistry(to: .init(source: "电池"), properties: ["Voltage": 13000, "InstantAmperage": 0]).batteryWatts)
    }
}
