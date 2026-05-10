import Foundation

public enum AppGroup {
    public static let id = "YOUR_TEAM_ID.industries.stark.boltbattery"
    public static let snapshotKey = "snapshot"
}

public enum BatterySnapshotStatus: String, Codable, Equatable, Sendable {
    case connected
    case receiverDisconnected
    case reconnecting
    case keyboardNoResponse
    case keyboardOffline
    case hidppError
    case error
}

public struct BatterySnapshot: Codable, Equatable, Sendable {
    public let sampledAt: Date
    public let socPercent: Int
    public let chargingState: String
    public let externalPower: Bool
    public let deviceName: String
    public let deviceType: String
    public let lastChargeEndedAt: Date?
    public let lastChargeEndedPercent: Int?
    public let status: BatterySnapshotStatus
    public let statusCode: UInt8?
    public let producerVersion: String

    public init(
        sampledAt: Date,
        socPercent: Int,
        chargingState: String,
        externalPower: Bool,
        deviceName: String,
        deviceType: String,
        lastChargeEndedAt: Date? = nil,
        lastChargeEndedPercent: Int? = nil,
        status: BatterySnapshotStatus = .connected,
        statusCode: UInt8? = nil,
        producerVersion: String
    ) {
        self.sampledAt = sampledAt
        self.socPercent = socPercent
        self.chargingState = chargingState
        self.externalPower = externalPower
        self.deviceName = deviceName
        self.deviceType = deviceType
        self.lastChargeEndedAt = lastChargeEndedAt
        self.lastChargeEndedPercent = lastChargeEndedPercent
        self.status = status
        self.statusCode = statusCode
        self.producerVersion = producerVersion
    }
}
