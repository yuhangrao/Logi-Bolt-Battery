import Cocoa
import BoltHIDPP
import WidgetKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    private static let dischargingPollInterval: TimeInterval = 5 * 60
    private static let chargingPollInterval: TimeInterval = 60
    private static let producerVersion: String =
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"
    private static let chargeEndingStates: Set<String> = [
        "charging",
        "charging-slow",
        "charging-full",
        "charging-error"
    ]
    private static let chargingPollStates: Set<String> = [
        "charging",
        "charging-slow",
        "charging-full",
        "charging-error",
        "recharging",
        "almost-full",
        "full",
        "slow-recharge"
    ]
    private static let batteryFeatureIDs: [UInt16] = [0x1004, 0x1000]
    private static let keyboardOfflineThreshold = 6

    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var deviceMenuItem: NSMenuItem!
    private var lastSampledMenuItem: NSMenuItem!

    private var lastSampledAt: Date?
    private var lastSOC: Int?
    private var lastDeviceName: String = "—"
    private var lastError: String?

    private var client: BoltClient?
    private var keyboardIndex: UInt8?
    private var batteryFeatureIndex: UInt8?
    private var currentPollInterval = AppDelegate.dischargingPollInterval
    private var keyboardNoResponseCount = 0
    private var isSampling = false
    private var needsSampleAfterCurrent = false
    private var eventSampleTask: Task<Void, Never>?
    private var isCharging = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        configureStatusItemIcon()
        buildMenu()
        requestSample()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func handleWake(_ note: Notification) {
        requestSample()
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        deviceMenuItem = NSMenuItem(title: "Sampling…", action: nil, keyEquivalent: "")
        deviceMenuItem.isEnabled = false
        menu.addItem(deviceMenuItem)

        lastSampledMenuItem = NSMenuItem(title: "Last sampled: never", action: nil, keyEquivalent: "")
        lastSampledMenuItem.isEnabled = false
        menu.addItem(lastSampledMenuItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.target = NSApp
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func configureStatusItemIcon() {
        guard let button = statusItem.button else { return }
        button.title = ""
        button.imagePosition = .imageOnly
        button.toolTip = "Bolt Battery"
        button.imageScaling = .scaleProportionallyDown
        refreshStatusItemIcon()
    }

    private func refreshStatusItemIcon() {
        guard let button = statusItem.button else { return }
        button.image = makeMenuBarImage(charging: isCharging)
    }

    private func makeMenuBarImage(charging: Bool) -> NSImage? {
        guard let logo = NSImage(named: "MenuBarBolt") else {
            NSLog("MenuBarBolt image asset not found")
            return nil
        }
        let size = NSSize(width: 20, height: 20)
        let composed = NSImage(size: size, flipped: false) { rect in
            logo.draw(in: rect)
            guard charging else { return true }

            let boltConfig = NSImage.SymbolConfiguration(pointSize: 9, weight: .bold)
            guard let bolt = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(boltConfig) else { return true }
            let boltSize = bolt.size
            let inset: CGFloat = 0
            let boltRect = NSRect(
                x: rect.maxX - boltSize.width - inset,
                y: rect.minY + inset,
                width: boltSize.width,
                height: boltSize.height
            )
            bolt.draw(in: boltRect)
            return true
        }
        composed.isTemplate = true
        return composed
    }

    private func requestSample() {
        Task { @MainActor [weak self] in await self?.sample() }
    }

    private func scheduleNextPoll() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: currentPollInterval, repeats: false) { _ in
            Task { @MainActor [weak self] in self?.requestSample() }
        }
    }

    private func sample() async {
        if isSampling {
            needsSampleAfterCurrent = true
            return
        }

        isSampling = true
        await runSample()
        isSampling = false

        if needsSampleAfterCurrent {
            needsSampleAfterCurrent = false
            requestSample()
            return
        }

        scheduleNextPoll()
    }

    private func runSample() async {
        let client: BoltClient
        do {
            client = try await currentClient()
        } catch {
            apply(error: error, keyboardNoResponse: false)
            return
        }

        var attemptedKeyboardSample = false
        do {
            let kbIdx: UInt8
            if let cachedIndex = keyboardIndex {
                kbIdx = cachedIndex
            } else {
                guard let discoveredIndex = try await client.discoverKeyboard() else {
                    keyboardIndex = nil
                    batteryFeatureIndex = nil
                    apply(missingKeyboard: ())
                    return
                }
                keyboardIndex = discoveredIndex
                kbIdx = discoveredIndex
            }

            attemptedKeyboardSample = true
            await updateBatteryFeatureIndex(client: client, deviceIndex: kbIdx)
            let battery = try await client.getBattery(deviceIndex: kbIdx)
            let name = (try? await client.getDeviceName(deviceIndex: kbIdx)) ?? "Keyboard"
            apply(battery: battery, name: name)
        } catch {
            await resetClient()
            apply(error: error, keyboardNoResponse: attemptedKeyboardSample && Self.isKeyboardNoResponse(error))
        }
    }

    private func currentClient() async throws -> BoltClient {
        if let client { return client }

        let newClient = try BoltClient()
        await newClient.setUnsolicitedReportHandler { [weak self] report in
            Task { @MainActor in
                self?.handleUnsolicitedReport(report)
            }
        }
        client = newClient
        return newClient
    }

    private func resetClient() async {
        let oldClient = client
        client = nil
        keyboardIndex = nil
        batteryFeatureIndex = nil
        await oldClient?.setUnsolicitedReportHandler(nil)
        await oldClient?.close()
    }

    private func updateBatteryFeatureIndex(client: BoltClient, deviceIndex: UInt8) async {
        guard batteryFeatureIndex == nil else { return }
        for featureID in Self.batteryFeatureIDs {
            if let index = try? await client.getFeatureIndex(deviceIndex: deviceIndex, featureID: featureID) {
                batteryFeatureIndex = index
                return
            }
        }
    }

    private func handleUnsolicitedReport(_ report: UnsolicitedReport) {
        guard isBatteryRelated(report) else { return }
        scheduleEventSample()
    }

    private func isBatteryRelated(_ report: UnsolicitedReport) -> Bool {
        guard let keyboardIndex,
              let batteryFeatureIndex,
              report.payload.count >= 2 else { return false }
        return report.payload[0] == keyboardIndex && report.payload[1] == batteryFeatureIndex
    }

    private func scheduleEventSample() {
        eventSampleTask?.cancel()
        eventSampleTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 1_500_000_000)
            } catch {
                return
            }
            self?.requestSample()
        }
    }

    private func apply(battery: BatteryReading, name: String) {
        keyboardNoResponseCount = 0
        lastError = nil
        lastSOC = battery.socPercent
        lastDeviceName = name
        let now = Date()
        lastSampledAt = now
        currentPollInterval = Self.chargingPollStates.contains(battery.chargingState) || battery.externalPower == true
            ? Self.chargingPollInterval
            : Self.dischargingPollInterval
        isCharging = battery.chargingState.lowercased().hasPrefix("charging")
        refreshStatusItemIcon()

        var deviceLine = "⌨ \(name) — \(battery.socPercent)%"
        var trailing: [String] = []
        if !battery.chargingState.isEmpty { trailing.append(battery.chargingState) }
        if battery.externalPower == true { trailing.append("plugged in") }
        if !trailing.isEmpty { deviceLine += " (\(trailing.joined(separator: ", ")))" }
        deviceMenuItem.title = deviceLine
        refreshSampledLine()

        let previous = SnapshotStore.shared.read()
        let didEndCharging = (
            previous.map { Self.chargeEndingStates.contains($0.chargingState) } == true
            && battery.chargingState == "discharging"
        )
        let lastChargeEndedAt = didEndCharging ? now : previous?.lastChargeEndedAt
        let lastChargeEndedPercent = didEndCharging ? battery.socPercent : previous?.lastChargeEndedPercent
        let snapshot = BatterySnapshot(
            sampledAt: now,
            socPercent: battery.socPercent,
            chargingState: battery.chargingState,
            externalPower: battery.externalPower ?? false,
            deviceName: name,
            deviceType: "Keyboard",
            lastChargeEndedAt: lastChargeEndedAt,
            lastChargeEndedPercent: lastChargeEndedPercent,
            lastError: nil,
            producerVersion: Self.producerVersion
        )
        SnapshotStore.shared.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func apply(missingKeyboard: ()) {
        let now = Date()
        let errorText = nextKeyboardNoResponseText()
        currentPollInterval = Self.dischargingPollInterval
        lastError = errorText
        lastSampledAt = now
        isCharging = false
        refreshStatusItemIcon()
        deviceMenuItem.title = errorText == "Keyboard offline" ? "Keyboard offline" : "No keyboard found among paired devices"
        refreshSampledLine()
        writeFailureSnapshot(lastError: errorText, sampledAt: now)
    }

    private func apply(error: Error, keyboardNoResponse: Bool) {
        let now = Date()
        let errorText = normalizedErrorText(for: error, keyboardNoResponse: keyboardNoResponse)
        currentPollInterval = Self.dischargingPollInterval
        lastError = errorText
        lastSampledAt = now
        isCharging = false
        refreshStatusItemIcon()
        deviceMenuItem.title = menuErrorTitle(for: errorText)
        refreshSampledLine()
        writeFailureSnapshot(lastError: errorText, sampledAt: now)
    }

    private func nextKeyboardNoResponseText() -> String {
        keyboardNoResponseCount += 1
        return keyboardNoResponseCount > Self.keyboardOfflineThreshold ? "Keyboard offline" : "Keyboard no response"
    }

    private func normalizedErrorText(for error: Error, keyboardNoResponse: Bool) -> String {
        if keyboardNoResponse { return nextKeyboardNoResponseText() }
        keyboardNoResponseCount = 0

        guard let boltError = error as? BoltError else {
            return "Error: \(String(describing: error))"
        }
        switch boltError {
        case .managerOpenFailed(_), .noMatchingDevice, .deviceOpenFailed(_), .setReportFailed(_):
            return "Receiver disconnected"
        case .hidppV1(let code, _, _), .hidppV2(let code, _, _, _):
            return String(format: "Error: 0x%02X", code)
        default:
            return "Error: \(boltError.description)"
        }
    }

    private static func isKeyboardNoResponse(_ error: Error) -> Bool {
        guard let boltError = error as? BoltError else { return false }
        switch boltError {
        case .timeout, .featureNotSupported:
            return true
        default:
            return false
        }
    }

    private func menuErrorTitle(for errorText: String) -> String {
        if errorText == "Receiver disconnected" || errorText == "Keyboard offline" {
            return errorText
        }
        return errorText.hasPrefix("Error:") ? errorText : "Error: \(errorText)"
    }

    private func writeFailureSnapshot(lastError: String, sampledAt: Date) {
        guard let previous = SnapshotStore.shared.read() else {
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        let snapshot = BatterySnapshot(
            sampledAt: sampledAt,
            socPercent: previous.socPercent,
            chargingState: previous.chargingState,
            externalPower: previous.externalPower,
            deviceName: previous.deviceName,
            deviceType: previous.deviceType,
            lastChargeEndedAt: previous.lastChargeEndedAt,
            lastChargeEndedPercent: previous.lastChargeEndedPercent,
            lastError: lastError,
            producerVersion: Self.producerVersion
        )
        SnapshotStore.shared.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func refreshSampledLine() {
        guard let t = lastSampledAt else {
            lastSampledMenuItem.title = "Last sampled: never"
            return
        }
        let now = Date()
        if now.timeIntervalSince(t) < 1 {
            lastSampledMenuItem.title = "Last sampled just now"
            return
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        lastSampledMenuItem.title = "Last sampled \(formatter.localizedString(for: t, relativeTo: now))"
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshSampledLine()
        requestSample()
    }
}
