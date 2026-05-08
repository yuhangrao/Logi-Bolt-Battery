import XCTest
@testable import BoltHIDPP

final class PingTests: XCTestCase {
    func testPingEchoesAA() async throws {
        let client: BoltClient
        do {
            client = try BoltClient()
        } catch {
            throw XCTSkip("Bolt receiver not present: \(error)")
        }
        defer { Task { await client.close() } }

        let echo = try await client.ping()
        XCTAssertEqual(echo, 0xAA, "Ping byte should round-trip unchanged")
    }
}
