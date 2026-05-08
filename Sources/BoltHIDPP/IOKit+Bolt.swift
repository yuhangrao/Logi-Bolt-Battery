import Foundation
import IOKit
import IOKit.hid

enum BoltHID {
    static let vendorID: Int = 0x046D
    static let productID: Int = 0xC548
    static let primaryUsagePage: Int = 0xFF00

    static let reportShort: UInt8 = 0x10
    static let reportLong: UInt8 = 0x11
    static let longReportLength = 20

    static let swid: UInt8 = 0x0F
    static let featureRoot: UInt8 = 0x00

    static let inputBufferSize = 64

    static func matchingDictionary() -> CFDictionary {
        let match: [String: Any] = [
            kIOHIDVendorIDKey as String: vendorID,
            kIOHIDProductIDKey as String: productID,
            kIOHIDPrimaryUsagePageKey as String: primaryUsagePage,
        ]
        return match as CFDictionary
    }
}

public enum BoltError: Error, CustomStringConvertible {
    case managerCreateFailed
    case managerOpenFailed(IOReturn)
    case noMatchingDevice
    case deviceOpenFailed(IOReturn)
    case setReportFailed(IOReturn)
    case timeout
    case clientClosed

    public var description: String {
        switch self {
        case .managerCreateFailed:
            return "IOHIDManagerCreate failed"
        case .managerOpenFailed(let r):
            return String(format: "IOHIDManagerOpen failed: 0x%08X", UInt32(bitPattern: r))
        case .noMatchingDevice:
            return "No matching HID device (Bolt receiver not present?)"
        case .deviceOpenFailed(let r):
            return String(format: "IOHIDDeviceOpen failed: 0x%08X", UInt32(bitPattern: r))
        case .setReportFailed(let r):
            return String(format: "IOHIDDeviceSetReport failed: 0x%08X", UInt32(bitPattern: r))
        case .timeout:
            return "HID++ response timeout"
        case .clientClosed:
            return "BoltClient is closed"
        }
    }
}
