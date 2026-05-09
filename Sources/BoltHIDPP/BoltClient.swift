import Foundation
import IOKit
import IOKit.hid

public struct UnsolicitedReport: Sendable, Equatable {
    public let reportID: UInt32
    public let payload: [UInt8]
}

public actor BoltClient {
    private let manager: IOHIDManager
    private let device: IOHIDDevice
    private let queue: DispatchQueue
    private let inputBuffer: UnsafeMutablePointer<UInt8>
    private var pending: PendingRequest?
    private var pendingNonce: UInt64 = 0
    private var unsolicitedReportHandler: (@Sendable (UnsolicitedReport) -> Void)?
    private var closed = false

    private struct PendingRequest {
        let deviceIndex: UInt8
        let featureIndex: UInt8
        let functionAndSwid: UInt8
        let nonce: UInt64
        let continuation: CheckedContinuation<[UInt8], Error>
    }

    public init() throws {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(mgr, BoltHID.matchingDictionary())
        let openResult = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
            throw BoltError.managerOpenFailed(openResult)
        }
        guard
            let devices = IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice>,
            let firstDevice = devices.first
        else {
            throw BoltError.noMatchingDevice
        }
        let dOpen = IOHIDDeviceOpen(firstDevice, IOOptionBits(kIOHIDOptionsTypeNone))
        guard dOpen == kIOReturnSuccess else {
            throw BoltError.deviceOpenFailed(dOpen)
        }

        let dispatchQueue = DispatchQueue(label: "industries.stark.boltbattery.hid")
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: BoltHID.inputBufferSize)
        buffer.initialize(repeating: 0, count: BoltHID.inputBufferSize)

        self.manager = mgr
        self.device = firstDevice
        self.queue = dispatchQueue
        self.inputBuffer = buffer

        let opaque = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(
            firstDevice,
            buffer,
            CFIndex(BoltHID.inputBufferSize),
            BoltClient.inputCallback,
            opaque
        )
        IOHIDDeviceSetDispatchQueue(firstDevice, dispatchQueue)
        IOHIDDeviceActivate(firstDevice)
    }

    deinit {
        inputBuffer.deinitialize(count: BoltHID.inputBufferSize)
        inputBuffer.deallocate()
    }

    // MARK: - Public protocol API

    public func ping() async throws -> UInt8 {
        try await getProtocolVersion(deviceIndex: 1).ping
    }

    public func getProtocolVersion(deviceIndex: UInt8, timeout: TimeInterval = 2.5) async throws -> ProtocolVersion {
        let response = try await call(
            deviceIndex: deviceIndex,
            featureIndex: HIDPP.rootIndex,
            function: 0x01,
            params: [0, 0, 0xAA],
            timeout: timeout
        )
        guard response.count >= 6 else { throw BoltError.invalidResponse }
        return ProtocolVersion(major: response[3], minor: response[4], ping: response[5])
    }

    public func getFeatureIndex(deviceIndex: UInt8, featureID: UInt16) async throws -> UInt8? {
        let hi = UInt8(featureID >> 8)
        let lo = UInt8(featureID & 0xFF)
        let response = try await call(
            deviceIndex: deviceIndex,
            featureIndex: HIDPP.rootIndex,
            function: 0x00,
            params: [hi, lo]
        )
        guard response.count >= 4 else { throw BoltError.invalidResponse }
        let idx = response[3]
        return idx == 0 ? nil : idx
    }

    public func getDeviceName(deviceIndex: UInt8) async throws -> String {
        guard let featIdx = try await getFeatureIndex(deviceIndex: deviceIndex, featureID: HIDPP.featureDeviceName) else {
            throw BoltError.featureNotSupported
        }
        let lengthResp = try await call(
            deviceIndex: deviceIndex,
            featureIndex: featIdx,
            function: 0x00,
            params: []
        )
        guard lengthResp.count >= 4 else { throw BoltError.invalidResponse }
        let totalLength = Int(lengthResp[3])

        var bytes: [UInt8] = []
        var offset = 0
        while offset < totalLength {
            let chunkResp = try await call(
                deviceIndex: deviceIndex,
                featureIndex: featIdx,
                function: 0x01,
                params: [UInt8(offset)]
            )
            guard chunkResp.count >= 4 else { break }
            let chunkSize = min(totalLength - offset, 16)
            let end = min(3 + chunkSize, chunkResp.count)
            let chunk = Array(chunkResp[3..<end])
            if chunk.isEmpty { break }
            bytes.append(contentsOf: chunk)
            offset += chunk.count
        }
        while bytes.last == 0 { bytes.removeLast() }
        return String(decoding: bytes, as: UTF8.self)
    }

    public func getDeviceType(deviceIndex: UInt8) async throws -> String {
        guard let featIdx = try await getFeatureIndex(deviceIndex: deviceIndex, featureID: HIDPP.featureDeviceName) else {
            throw BoltError.featureNotSupported
        }
        let response = try await call(
            deviceIndex: deviceIndex,
            featureIndex: featIdx,
            function: 0x02,
            params: []
        )
        guard response.count >= 4 else { throw BoltError.invalidResponse }
        let raw = response[3]
        return HIDPP.deviceTypeNames[raw] ?? "Unknown(\(raw))"
    }

    public func getBattery(deviceIndex: UInt8) async throws -> BatteryReading {
        if let unifiedIdx = try await getFeatureIndex(deviceIndex: deviceIndex, featureID: HIDPP.featureBatteryUnified) {
            let response = try await call(
                deviceIndex: deviceIndex,
                featureIndex: unifiedIdx,
                function: 0x01,
                params: []
            )
            guard response.count >= 6 else { throw BoltError.invalidResponse }
            let stateRaw = response[5]
            let chargeState = HIDPP.chargingStateUnified[stateRaw] ?? "unknown(\(stateRaw))"
            let externalPower: Bool? = response.count > 6 ? response[6] != 0 : nil
            return BatteryReading(
                socPercent: Int(response[3]),
                chargingState: chargeState,
                externalPower: externalPower,
                feature: BatteryReading.unifiedFeatureLabel
            )
        }
        if let legacyIdx = try await getFeatureIndex(deviceIndex: deviceIndex, featureID: HIDPP.featureBatteryLegacy) {
            let response = try await call(
                deviceIndex: deviceIndex,
                featureIndex: legacyIdx,
                function: 0x00,
                params: []
            )
            guard response.count >= 6 else { throw BoltError.invalidResponse }
            let statusRaw = response[5]
            let status = HIDPP.chargingStatusLegacy[statusRaw] ?? "unknown(\(statusRaw))"
            return BatteryReading(
                socPercent: Int(response[3]),
                chargingState: status,
                externalPower: nil,
                feature: BatteryReading.legacyFeatureLabel
            )
        }
        throw BoltError.featureNotSupported
    }

    public func getFirmware(deviceIndex: UInt8) async throws -> [FirmwareInfo] {
        guard let featIdx = try await getFeatureIndex(deviceIndex: deviceIndex, featureID: HIDPP.featureDeviceInfo) else {
            throw BoltError.featureNotSupported
        }
        let countResp = try await call(
            deviceIndex: deviceIndex,
            featureIndex: featIdx,
            function: 0x00,
            params: []
        )
        guard countResp.count >= 4 else { throw BoltError.invalidResponse }
        let count = Int(countResp[3])

        var infos: [FirmwareInfo] = []
        for i in 0..<count {
            do {
                let info = try await call(
                    deviceIndex: deviceIndex,
                    featureIndex: featIdx,
                    function: 0x01,
                    params: [UInt8(i)]
                )
                guard info.count >= 11 else { continue }
                let kindByte = info[3] & 0x0F
                let kind = HIDPP.firmwareKindNames[kindByte] ?? String(format: "k0x%x", info[3])
                var nameBytes = Array(info[4..<7])
                while nameBytes.last == 0 { nameBytes.removeLast() }
                let name = String(bytes: nameBytes, encoding: .ascii) ?? ""
                let build = (UInt16(info[9]) << 8) | UInt16(info[10])
                let version = String(format: "%02x.%02x.B%04X", info[7], info[8], build)
                infos.append(FirmwareInfo(kind: kind, name: name, version: version))
            } catch {
                continue
            }
        }
        return infos
    }

    public func discoverKeyboard() async throws -> UInt8? {
        for idx: UInt8 in 1...6 {
            do {
                _ = try await getProtocolVersion(deviceIndex: idx)
                let type = try await getDeviceType(deviceIndex: idx)
                if type == "Keyboard" { return idx }
            } catch {
                continue
            }
        }
        return nil
    }

    public func setUnsolicitedReportHandler(_ handler: (@Sendable (UnsolicitedReport) -> Void)?) {
        unsolicitedReportHandler = handler
    }

    public func close() {
        guard !closed else { return }
        closed = true
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if let p = pending {
            pending = nil
            p.continuation.resume(throwing: BoltError.clientClosed)
        }
    }

    // MARK: - Private call

    private func call(
        deviceIndex: UInt8,
        featureIndex: UInt8,
        function: UInt8,
        params: [UInt8],
        timeout: TimeInterval = 2.5
    ) async throws -> [UInt8] {
        guard !closed else { throw BoltError.clientClosed }
        let functionAndSwid = (function << 4) | (HIDPP.swid & 0x0F)

        var buf = [UInt8](repeating: 0, count: HIDPP.longReportLength)
        buf[0] = HIDPP.reportLong
        buf[1] = deviceIndex
        buf[2] = featureIndex
        buf[3] = functionAndSwid
        for (i, p) in params.prefix(16).enumerated() {
            buf[4 + i] = p
        }

        pendingNonce &+= 1
        let nonce = pendingNonce
        let timeoutNanos = UInt64(timeout * 1_000_000_000)

        let response: [UInt8] = try await withCheckedThrowingContinuation { cont in
            self.pending = PendingRequest(
                deviceIndex: deviceIndex,
                featureIndex: featureIndex,
                functionAndSwid: functionAndSwid,
                nonce: nonce,
                continuation: cont
            )

            let result = buf.withUnsafeBufferPointer { ptr -> IOReturn in
                IOHIDDeviceSetReport(
                    self.device,
                    kIOHIDReportTypeOutput,
                    CFIndex(HIDPP.reportLong),
                    ptr.baseAddress!,
                    CFIndex(ptr.count)
                )
            }
            if result != kIOReturnSuccess {
                self.pending = nil
                cont.resume(throwing: BoltError.setReportFailed(result))
                return
            }

            Task { [weak self] in
                try? await Task.sleep(nanoseconds: timeoutNanos)
                await self?.timeoutPending(nonce: nonce)
            }
        }

        if response.count >= 5,
           response[1] == HIDPP.errorSubID_v1,
           response[3] == functionAndSwid {
            let code = response[4]
            let name = HIDPP.v1ErrorNames[code] ?? "?"
            throw BoltError.hidppV1(code: code, name: name, deviceIndex: deviceIndex)
        }
        if response.count >= 6,
           response[1] == HIDPP.errorFeatureIndex_v2,
           response[3] == featureIndex,
           (response[4] >> 4) == function {
            let code = response[5]
            let name = HIDPP.v2ErrorNames[code] ?? "?"
            throw BoltError.hidppV2(code: code, name: name, deviceIndex: deviceIndex, featureIndex: featureIndex)
        }
        return response
    }

    private func timeoutPending(nonce: UInt64) {
        guard let p = pending, p.nonce == nonce else { return }
        pending = nil
        p.continuation.resume(throwing: BoltError.timeout)
    }

    private func notifyUnsolicited(reportID: UInt32, payload: [UInt8]) {
        unsolicitedReportHandler?(UnsolicitedReport(reportID: reportID, payload: payload))
    }

    fileprivate func handleReport(reportID: UInt32, bytes: [UInt8]) {
        var data = bytes
        if let first = data.first, first == UInt8(reportID & 0xFF) {
            data.removeFirst()
        }
        guard data.count >= 4 else {
            notifyUnsolicited(reportID: reportID, payload: data)
            return
        }
        guard let p = pending else {
            notifyUnsolicited(reportID: reportID, payload: data)
            return
        }

        if data[0] == p.deviceIndex,
           data[1] == HIDPP.errorSubID_v1,
           data[3] == p.functionAndSwid {
            pending = nil
            p.continuation.resume(returning: data)
            return
        }
        if data.count >= 5,
           data[0] == p.deviceIndex,
           data[1] == HIDPP.errorFeatureIndex_v2,
           data[3] == p.featureIndex,
           (data[4] >> 4) == (p.functionAndSwid >> 4) {
            pending = nil
            p.continuation.resume(returning: data)
            return
        }

        guard data[0] == p.deviceIndex,
              data[1] == p.featureIndex,
              (data[2] & 0x0F) == (p.functionAndSwid & 0x0F)
        else {
            notifyUnsolicited(reportID: reportID, payload: data)
            return
        }

        pending = nil
        p.continuation.resume(returning: data)
    }

    private static let inputCallback: IOHIDReportCallback = { context, _, _, _, reportID, report, length in
        guard let context = context else { return }
        let client = Unmanaged<BoltClient>.fromOpaque(context).takeUnretainedValue()
        let bytes = Array(UnsafeBufferPointer(start: report, count: Int(length)))
        Task { await client.handleReport(reportID: reportID, bytes: bytes) }
    }
}
