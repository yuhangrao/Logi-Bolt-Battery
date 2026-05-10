import Foundation
import IOKit
import IOKit.hid

public enum BoltReceiverPresenceEvent: Sendable, Equatable {
    case matched
    case removed
}

public final class BoltReceiverMonitor {
    private final class CallbackContext {
        weak var monitor: BoltReceiverMonitor?

        init(_ monitor: BoltReceiverMonitor) {
            self.monitor = monitor
        }
    }

    private let manager: IOHIDManager
    private let handler: @Sendable (BoltReceiverPresenceEvent) -> Void
    private var callbackContext: Unmanaged<CallbackContext>?
    private var isStarted = false

    public init(handler: @escaping @Sendable (BoltReceiverPresenceEvent) -> Void) throws {
        self.manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.handler = handler

        IOHIDManagerSetDeviceMatching(manager, BoltHID.matchingDictionary())
        let context = Unmanaged.passRetained(CallbackContext(self))
        callbackContext = context
        let opaque = context.toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, Self.matchingCallback, opaque)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, Self.removalCallback, opaque)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            callbackContext?.release()
            callbackContext = nil
            throw BoltError.managerOpenFailed(openResult)
        }
        isStarted = true
    }

    deinit {
        stop()
    }

    public static func isReceiverPresent() -> Bool {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, BoltHID.matchingDictionary())
        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else { return false }
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return false }
        return !devices.isEmpty
    }

    public func stop() {
        guard isStarted else { return }
        isStarted = false
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        callbackContext?.release()
        callbackContext = nil
    }

    private func handle(_ event: BoltReceiverPresenceEvent) {
        guard isStarted else { return }
        handler(event)
    }

    private static let matchingCallback: IOHIDDeviceCallback = { context, _, _, _ in
        guard let context else { return }
        Unmanaged<CallbackContext>.fromOpaque(context).takeUnretainedValue().monitor?.handle(.matched)
    }

    private static let removalCallback: IOHIDDeviceCallback = { context, _, _, _ in
        guard let context else { return }
        Unmanaged<CallbackContext>.fromOpaque(context).takeUnretainedValue().monitor?.handle(.removed)
    }
}
