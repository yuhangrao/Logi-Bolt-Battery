import XCTest
@testable import BoltHIDPP

final class UnsolicitedReportTests: XCTestCase {
    func testReceiverNotificationSubID() {
        let report = UnsolicitedReport(reportID: UInt32(HIDPP.reportShort), payload: [0x01, HIDPP.notificationDeviceConnected, 0x10, 0x01])
        XCTAssertEqual(report.receiverNotificationSubID, HIDPP.notificationDeviceConnected)
        XCTAssertFalse(report.indicatesConnectionLoss)
    }

    func testRejectsMalformedReceiverNotifications() {
        let longReportCollision = UnsolicitedReport(reportID: UInt32(HIDPP.reportLong), payload: [0x01, HIDPP.notificationDeviceConnected, 0x10, 0x01])
        let shortConnected = UnsolicitedReport(reportID: UInt32(HIDPP.reportShort), payload: [0x01, HIDPP.notificationDeviceConnected, 0x10])
        let tooShort = UnsolicitedReport(reportID: UInt32(HIDPP.reportShort), payload: [0x01, HIDPP.notificationDeviceDisconnected])
        XCTAssertNil(longReportCollision.receiverNotificationSubID)
        XCTAssertNil(shortConnected.receiverNotificationSubID)
        XCTAssertNil(tooShort.receiverNotificationSubID)
    }

    func testReceiverConnectionLossNotifications() {
        let disconnected = UnsolicitedReport(reportID: UInt32(HIDPP.reportShort), payload: [0x01, HIDPP.notificationDeviceDisconnected, 0x00])
        let linkLostStatus = UnsolicitedReport(reportID: UInt32(HIDPP.reportShort), payload: [0x01, HIDPP.notificationConnectionStatus, 0x01])
        let nonLossStatus = UnsolicitedReport(reportID: UInt32(HIDPP.reportShort), payload: [0x01, HIDPP.notificationConnectionStatus, 0x00])
        let connectedWithNoLink = UnsolicitedReport(reportID: UInt32(HIDPP.reportShort), payload: [0x01, HIDPP.notificationDeviceConnected, 0x10, 0x41, 0x78, 0xB3])
        let connectedWithLink = UnsolicitedReport(reportID: UInt32(HIDPP.reportShort), payload: [0x01, HIDPP.notificationDeviceConnected, 0x10, 0x01, 0x78, 0xB3])
        XCTAssertTrue(disconnected.indicatesConnectionLoss)
        XCTAssertTrue(linkLostStatus.indicatesConnectionLoss)
        XCTAssertFalse(nonLossStatus.indicatesConnectionLoss)
        XCTAssertTrue(connectedWithNoLink.indicatesConnectionLoss)
        XCTAssertFalse(connectedWithLink.indicatesConnectionLoss)
    }

    func testFeatureReportMatching() {
        let report = UnsolicitedReport(reportID: UInt32(HIDPP.reportLong), payload: [0x01, 0x08, 0x00, 0x4B])
        let shortReportCollision = UnsolicitedReport(reportID: UInt32(HIDPP.reportShort), payload: [0x01, 0x08, 0x00, 0x4B])
        let malformed = UnsolicitedReport(reportID: UInt32(HIDPP.reportLong), payload: [0x01, 0x08])
        XCTAssertTrue(report.matchesFeatureReport(deviceIndex: 0x01, featureIndex: 0x08))
        XCTAssertFalse(report.matchesFeatureReport(deviceIndex: 0x02, featureIndex: 0x08))
        XCTAssertFalse(report.matchesFeatureReport(deviceIndex: 0x01, featureIndex: 0x09))
        XCTAssertFalse(shortReportCollision.matchesFeatureReport(deviceIndex: 0x01, featureIndex: 0x08))
        XCTAssertFalse(malformed.matchesFeatureReport(deviceIndex: 0x01, featureIndex: 0x08))
    }
}
