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

    private static let pollInterval: TimeInterval = 5 * 60
    private static let producerVersion: String =
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"

    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var deviceMenuItem: NSMenuItem!
    private var lastSampledMenuItem: NSMenuItem!

    private var lastSampledAt: Date?
    private var lastSOC: Int?
    private var lastDeviceName: String = "—"
    private var lastError: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "⌨ —"
        buildMenu()
        Task { await self.sample() }
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { _ in
            Task { @MainActor [weak self] in await self?.sample() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func handleWake(_ note: Notification) {
        Task { @MainActor [weak self] in await self?.sample() }
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

    private func sample() async {
        let client: BoltClient
        do {
            client = try BoltClient()
        } catch {
            apply(error: error)
            return
        }

        do {
            guard let kbIdx = try await client.discoverKeyboard() else {
                await client.close()
                apply(missingKeyboard: ())
                return
            }
            let battery = try await client.getBattery(deviceIndex: kbIdx)
            let name = (try? await client.getDeviceName(deviceIndex: kbIdx)) ?? "Keyboard"
            await client.close()
            apply(battery: battery, name: name)
        } catch {
            await client.close()
            apply(error: error)
        }
    }

    private func apply(battery: BatteryReading, name: String) {
        lastError = nil
        lastSOC = battery.socPercent
        lastDeviceName = name
        let now = Date()
        lastSampledAt = now

        statusItem.button?.title = "⌨ \(battery.socPercent)%"

        var deviceLine = "⌨ \(name) — \(battery.socPercent)%"
        var trailing: [String] = []
        if !battery.chargingState.isEmpty { trailing.append(battery.chargingState) }
        if battery.externalPower == true { trailing.append("plugged in") }
        if !trailing.isEmpty { deviceLine += " (\(trailing.joined(separator: ", ")))" }
        deviceMenuItem.title = deviceLine
        refreshSampledLine()

        let previous = SnapshotStore.shared.read()
        let snapshot = BatterySnapshot(
            sampledAt: now,
            socPercent: battery.socPercent,
            chargingState: battery.chargingState,
            externalPower: battery.externalPower ?? false,
            deviceName: name,
            deviceType: "Keyboard",
            lastChargeEndedAt: previous?.lastChargeEndedAt,
            lastChargeEndedPercent: previous?.lastChargeEndedPercent,
            lastError: nil,
            producerVersion: Self.producerVersion
        )
        SnapshotStore.shared.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func apply(missingKeyboard: ()) {
        lastError = "No keyboard found"
        lastSampledAt = Date()
        statusItem.button?.title = "⌨ ?"
        deviceMenuItem.title = "No keyboard found among paired devices"
        refreshSampledLine()
    }

    private func apply(error: Error) {
        lastError = String(describing: error)
        lastSampledAt = Date()
        statusItem.button?.title = "⌨ ?"
        deviceMenuItem.title = "Error: \(lastError ?? "unknown")"
        refreshSampledLine()
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
    }
}
