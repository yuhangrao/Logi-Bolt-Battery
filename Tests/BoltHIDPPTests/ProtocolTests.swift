import XCTest
@testable import BoltHIDPP

final class ProtocolTests: XCTestCase {
    private func makeClient() throws -> BoltClient {
        do {
            return try BoltClient()
        } catch {
            throw XCTSkip("Bolt receiver not present: \(error)")
        }
    }

    func testDiscoverKeyboard() async throws {
        let client = try makeClient()
        defer { Task { await client.close() } }
        let idx = try await client.discoverKeyboard()
        XCTAssertNotNil(idx, "Expected a keyboard paired to the Bolt receiver")
        if let idx = idx {
            XCTAssertGreaterThanOrEqual(idx, 1)
            XCTAssertLessThanOrEqual(idx, 6)
        }
    }

    func testReadKeyboardMetadata() async throws {
        let client = try makeClient()
        defer { Task { await client.close() } }
        guard let idx = try await client.discoverKeyboard() else {
            throw XCTSkip("No keyboard paired")
        }
        let name = try await client.getDeviceName(deviceIndex: idx)
        XCTAssertFalse(name.isEmpty, "Device name should not be empty")
        let type = try await client.getDeviceType(deviceIndex: idx)
        XCTAssertEqual(type, "Keyboard")
    }

    func testReadBattery() async throws {
        let client = try makeClient()
        defer { Task { await client.close() } }
        guard let idx = try await client.discoverKeyboard() else {
            throw XCTSkip("No keyboard paired")
        }
        let battery = try await client.getBattery(deviceIndex: idx)
        XCTAssertGreaterThanOrEqual(battery.socPercent, 0)
        XCTAssertLessThanOrEqual(battery.socPercent, 100)
        XCTAssertFalse(battery.chargingState.isEmpty)
        XCTAssertTrue(
            battery.feature == BatteryReading.unifiedFeatureLabel ||
            battery.feature == BatteryReading.legacyFeatureLabel
        )
    }

    func testReadFirmware() async throws {
        let client = try makeClient()
        defer { Task { await client.close() } }
        guard let idx = try await client.discoverKeyboard() else {
            throw XCTSkip("No keyboard paired")
        }
        let firmwares = try await client.getFirmware(deviceIndex: idx)
        XCTAssertFalse(firmwares.isEmpty, "Expected at least one firmware entry")
        for fw in firmwares {
            XCTAssertFalse(fw.kind.isEmpty)
            XCTAssertFalse(fw.version.isEmpty)
        }
    }
}
