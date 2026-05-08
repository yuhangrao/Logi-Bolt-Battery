import Foundation

public enum AppGroup {
    public static let id = "YOUR_TEAM_ID.industries.stark.boltbattery"
    public static let snapshotKey = "snapshot"
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
    public let lastError: String?
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
        lastError: String? = nil,
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
        self.lastError = lastError
        self.producerVersion = producerVersion
    }
}
