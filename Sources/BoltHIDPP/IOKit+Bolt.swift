import Foundation
import IOKit
import IOKit.hid

enum BoltHID {
    static let vendorID: Int = 0x046D
    static let productID: Int = 0xC548
    static let primaryUsagePage: Int = 0xFF00

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
