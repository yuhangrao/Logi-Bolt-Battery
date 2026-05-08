import Foundation
import IOKit
import IOKit.hid

public actor BoltClient {
    private let manager: IOHIDManager
    private let device: IOHIDDevice
    private let queue: DispatchQueue
    private let inputBuffer: UnsafeMutablePointer<UInt8>
    private var pending: PendingRequest?
    private var pendingNonce: UInt64 = 0
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

    public func ping() async throws -> UInt8 {
        guard !closed else { throw BoltError.clientClosed }

        let deviceIndex: UInt8 = 1
        let featureIndex = BoltHID.featureRoot
        let function: UInt8 = 0x01
        let functionAndSwid = (function << 4) | (BoltHID.swid & 0x0F)

        var buf = [UInt8](repeating: 0, count: BoltHID.longReportLength)
        buf[0] = BoltHID.reportLong
        buf[1] = deviceIndex
        buf[2] = featureIndex
        buf[3] = functionAndSwid
        buf[6] = 0xAA

        pendingNonce &+= 1
        let nonce = pendingNonce

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
                    CFIndex(BoltHID.reportLong),
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
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                await self?.timeoutPending(nonce: nonce)
            }
        }

        guard response.count >= 6 else { throw BoltError.timeout }
        return response[5]
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

    private func timeoutPending(nonce: UInt64) {
        guard let p = pending, p.nonce == nonce else { return }
        pending = nil
        p.continuation.resume(throwing: BoltError.timeout)
    }

    fileprivate func handleReport(reportID: UInt32, bytes: [UInt8]) {
        var data = bytes
        if let first = data.first, first == UInt8(reportID & 0xFF) {
            data.removeFirst()
        }
        guard data.count >= 4, let p = pending else { return }

        if data[0] == p.deviceIndex,
           data[1] == 0x8F,
           data[3] == p.functionAndSwid {
            pending = nil
            p.continuation.resume(returning: data)
            return
        }
        if data[0] == p.deviceIndex,
           data[1] == 0xFF,
           data[3] == p.featureIndex,
           (data[4] >> 4) == (p.functionAndSwid >> 4) {
            pending = nil
            p.continuation.resume(returning: data)
            return
        }

        guard data[0] == p.deviceIndex,
              data[1] == p.featureIndex,
              (data[2] & 0x0F) == (p.functionAndSwid & 0x0F)
        else { return }

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
