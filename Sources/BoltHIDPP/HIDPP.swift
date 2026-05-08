import Foundation
import IOKit

enum HIDPP {
    static let reportShort: UInt8 = 0x10
    static let reportLong: UInt8 = 0x11
    static let longReportLength = 20

    static let swid: UInt8 = 0x0F

    static let rootIndex: UInt8 = 0x00
    static let errorSubID_v1: UInt8 = 0x8F
    static let errorFeatureIndex_v2: UInt8 = 0xFF

    static let featureRoot: UInt16 = 0x0000
    static let featureFeatureSet: UInt16 = 0x0001
    static let featureDeviceInfo: UInt16 = 0x0003
    static let featureDeviceName: UInt16 = 0x0005
    static let featureBatteryLegacy: UInt16 = 0x1000
    static let featureBatteryUnified: UInt16 = 0x1004

    static let v1ErrorNames: [UInt8: String] = [
        0x01: "InvalidSubID",
        0x02: "InvalidAddress",
        0x03: "InvalidValue",
        0x04: "ConnectionNotEstablished",
        0x05: "TooManyDevices",
        0x06: "AlreadyExists",
        0x07: "Busy",
        0x08: "UnknownDevice",
        0x09: "ResourceError",
        0x0A: "RequestUnavailable",
        0x0B: "InvalidParamValue",
        0x0C: "WrongPINCode",
    ]

    static let v2ErrorNames: [UInt8: String] = [
        0x01: "Unknown",
        0x02: "InvalidArgument",
        0x03: "OutOfRange",
        0x04: "HWError",
        0x05: "LogitechInternal",
        0x06: "InvalidFeatureIndex",
        0x07: "InvalidFunctionID",
        0x08: "Busy",
        0x09: "Unsupported",
    ]

    static let deviceTypeNames: [UInt8: String] = [
        0: "Keyboard", 1: "RemoteControl", 2: "Numpad", 3: "Mouse",
        4: "Trackpad", 5: "Trackball", 6: "Presenter", 7: "Receiver",
        8: "Headset", 9: "Webcam", 10: "SteeringWheel", 11: "Joystick",
        12: "Gamepad", 13: "Dock", 14: "Speaker", 15: "Microphone",
        16: "IlluminationLight", 17: "ProgrammableController",
        18: "CarSimPedals", 19: "Adapter",
    ]

    static let chargingStateUnified: [UInt8: String] = [
        0: "discharging", 1: "charging", 2: "charging-slow",
        3: "charging-full", 4: "charging-error",
    ]

    static let chargingStatusLegacy: [UInt8: String] = [
        0: "discharging", 1: "recharging", 2: "almost-full",
        3: "full", 4: "slow-recharge", 5: "invalid-battery",
        6: "thermal-error",
    ]

    static let firmwareKindNames: [UInt8: String] = [
        0: "MainApp", 1: "Bootloader", 2: "Hardware",
    ]
}

public struct ProtocolVersion: Sendable, Equatable {
    public let major: UInt8
    public let minor: UInt8
    public let ping: UInt8
}

public struct BatteryReading: Sendable, Equatable {
    public let socPercent: Int
    public let chargingState: String
    public let externalPower: Bool?
    public let feature: String

    public static let unifiedFeatureLabel = "UnifiedBattery (0x1004)"
    public static let legacyFeatureLabel = "BatteryUnifiedLevelStatus (0x1000)"
}

public struct FirmwareInfo: Sendable, Equatable, CustomStringConvertible {
    public let kind: String
    public let name: String
    public let version: String

    public var description: String { "\(kind) \(name) v\(version)" }
}

public enum BoltError: Error, CustomStringConvertible {
    case managerOpenFailed(IOReturn)
    case noMatchingDevice
    case deviceOpenFailed(IOReturn)
    case setReportFailed(IOReturn)
    case timeout
    case clientClosed
    case invalidResponse
    case featureNotSupported
    case hidppV1(code: UInt8, name: String, deviceIndex: UInt8)
    case hidppV2(code: UInt8, name: String, deviceIndex: UInt8, featureIndex: UInt8)

    public var description: String {
        switch self {
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
        case .invalidResponse:
            return "HID++ response too short to parse"
        case .featureNotSupported:
            return "Feature not exposed by device"
        case .hidppV1(let code, let name, let dev):
            return String(format: "HID++1 err 0x%02x (%@) on device %d", code, name, dev)
        case .hidppV2(let code, let name, let dev, let feat):
            return String(format: "HID++2 err 0x%02x (%@) on device %d feature 0x%02x", code, name, dev, feat)
        }
    }
}
