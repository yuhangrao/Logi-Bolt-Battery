import WidgetKit
import SwiftUI

private enum WidgetTiming {
    static let staleInterval: TimeInterval = 30 * 60
    static let staleRefreshInterval: TimeInterval = 15 * 60
}

struct BoltBatteryEntry: TimelineEntry {
    let date: Date
    let snapshot: BatterySnapshot?

    static let placeholder = BoltBatteryEntry(
        date: Date(),
        snapshot: BatterySnapshot(
            sampledAt: Date(),
            socPercent: 75,
            chargingState: "discharging",
            externalPower: false,
            deviceName: "MX Keys S",
            deviceType: "Keyboard",
            producerVersion: "0.1.0"
        )
    )
}

struct BoltBatteryProvider: TimelineProvider {
    func placeholder(in context: Context) -> BoltBatteryEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (BoltBatteryEntry) -> Void) {
        let snapshot = SnapshotStore.shared.read()
        completion(BoltBatteryEntry(date: Date(), snapshot: snapshot ?? BoltBatteryEntry.placeholder.snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BoltBatteryEntry>) -> Void) {
        let now = Date()
        let snapshot = SnapshotStore.shared.read()
        let entry = BoltBatteryEntry(date: now, snapshot: snapshot)
        guard let snapshot else {
            completion(Timeline(entries: [entry], policy: .never))
            return
        }

        let staleDate = snapshot.sampledAt.addingTimeInterval(WidgetTiming.staleInterval + 1)
        if now < staleDate {
            let staleEntry = BoltBatteryEntry(date: staleDate, snapshot: snapshot)
            completion(Timeline(
                entries: [entry, staleEntry],
                policy: .after(staleDate.addingTimeInterval(WidgetTiming.staleRefreshInterval))
            ))
        } else {
            completion(Timeline(
                entries: [entry],
                policy: .after(now.addingTimeInterval(WidgetTiming.staleRefreshInterval))
            ))
        }
    }
}

private enum WidgetDisplayState {
    case missing
    case stale(BatterySnapshot)
    case receiverDisconnected(BatterySnapshot)
    case keyboardOffline(BatterySnapshot)
    case sampleError(BatterySnapshot, String)
    case normal(BatterySnapshot)

    var snapshot: BatterySnapshot? {
        switch self {
        case .missing:
            return nil
        case .stale(let snapshot),
             .receiverDisconnected(let snapshot),
             .keyboardOffline(let snapshot),
             .sampleError(let snapshot, _),
             .normal(let snapshot):
            return snapshot
        }
    }

    var forcesGrayRing: Bool {
        switch self {
        case .missing, .receiverDisconnected, .keyboardOffline, .sampleError:
            return true
        case .stale, .normal:
            return false
        }
    }

    var contentOpacity: Double {
        switch self {
        case .stale:
            return 0.5
        default:
            return 1
        }
    }

    var showsChargingIndicator: Bool {
        guard case .normal(let snapshot) = self else { return false }
        return snapshot.chargingState.lowercased().hasPrefix("charging")
    }
}

private struct BatteryRing: View {
    let socPercent: Int?
    let isCharging: Bool
    let glyphSymbolName: String
    let forceGray: Bool

    private let lineWidth: CGFloat = 6.5
    private let boltSize: CGFloat = 10
    private let chargingGapDegrees: Double = 40

    var body: some View {
        GeometryReader { geo in
            let radius = min(geo.size.width, geo.size.height) / 2
            let gapFraction: CGFloat = isCharging ? CGFloat(chargingGapDegrees / 360) : 0
            let gapHalf = gapFraction / 2
            let availableArc = 1 - gapFraction
            let progressEnd = gapHalf + ringFraction * availableArc

            ZStack {
                Circle()
                    .trim(from: gapHalf, to: 1 - gapHalf)
                    .stroke(
                        Color.secondary.opacity(0.22),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Circle()
                    .trim(from: gapHalf, to: progressEnd)
                    .stroke(
                        ringColor,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                Image(systemName: glyphSymbolName)
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(.primary)

                if isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: boltSize, weight: .bold))
                        .foregroundStyle(boltColor)
                        .offset(y: -radius)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private var ringFraction: CGFloat {
        guard let s = socPercent else { return 0 }
        return max(0, min(1, CGFloat(s) / 100.0))
    }

    private var ringColor: Color {
        if forceGray { return .gray }
        if isCharging { return .green }
        guard let s = socPercent else { return .gray }
        return s <= 20 ? .red : .green
    }

    private var boltColor: Color {
        guard let s = socPercent else { return .white }
        return s >= 100 ? .green : .white
    }
}

struct BoltBatteryWidgetEntryView: View {
    let entry: BoltBatteryEntry

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let gridRingDiameter = side * 11 / 28
            let ringDiameter = side * 5 / 14
            let horizontalGap = (geo.size.width - 2 * gridRingDiameter) / 3
            let verticalGap = (geo.size.height - 2 * gridRingDiameter) / 3
            let topRowCenterY = verticalGap + gridRingDiameter / 2
            let ringCenterX = horizontalGap + gridRingDiameter / 2
            let ringRight = ringCenterX + ringDiameter / 2
            let percentCenterX = (ringRight + geo.size.width) / 2
            let bottomRowCenterY = 2 * verticalGap + gridRingDiameter * 1.5
            let state = displayState

            ZStack(alignment: .topLeading) {
                BatteryRing(
                    socPercent: state.snapshot?.socPercent,
                    isCharging: state.showsChargingIndicator,
                    glyphSymbolName: "keyboard",
                    forceGray: state.forcesGrayRing
                )
                .frame(width: ringDiameter, height: ringDiameter)
                .opacity(state.contentOpacity)
                .position(x: ringCenterX, y: topRowCenterY)

                Text(percentText(for: state))
                    .font(.system(size: 31, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .fixedSize()
                    .opacity(state.contentOpacity)
                    .position(x: percentCenterX, y: topRowCenterY)

                footerText(for: state)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(width: geo.size.width - 2 * horizontalGap)
                    .position(x: geo.size.width / 2, y: bottomRowCenterY)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private var displayState: WidgetDisplayState {
        guard let snapshot = entry.snapshot else { return .missing }
        if entry.date.timeIntervalSince(snapshot.sampledAt) > WidgetTiming.staleInterval {
            return .stale(snapshot)
        }
        guard let lastError = snapshot.lastError else { return .normal(snapshot) }
        if lastError == "Receiver disconnected" {
            return .receiverDisconnected(snapshot)
        }
        if lastError == "Keyboard offline" {
            return .keyboardOffline(snapshot)
        }
        if lastError.hasPrefix("Error:") {
            return .sampleError(snapshot, lastError)
        }
        return .normal(snapshot)
    }

    private func percentText(for state: WidgetDisplayState) -> String {
        guard let soc = state.snapshot?.socPercent else { return "—%" }
        return "\(soc)%"
    }

    private func footerText(for state: WidgetDisplayState) -> Text {
        switch state {
        case .missing:
            return Text("Open Bolt Battery to start")
        case .stale(let snapshot):
            return Text("Updated \(compactElapsedText(since: snapshot.sampledAt, relativeTo: entry.date))")
        case .receiverDisconnected:
            return Text("Receiver disconnected")
        case .keyboardOffline:
            return Text("Keyboard offline")
        case .sampleError(_, let errorText):
            return Text(errorText)
        case .normal(let snapshot):
            guard let lastChargeEndedAt = snapshot.lastChargeEndedAt,
                  let lastChargeEndedPercent = snapshot.lastChargeEndedPercent else {
                return Text("Charge to start tracking")
            }
            return Text("Last charged: \(lastChargeEndedPercent)% · \(compactElapsedText(since: lastChargeEndedAt, relativeTo: entry.date))")
        }
    }

    private func compactElapsedText(since date: Date, relativeTo referenceDate: Date) -> String {
        let seconds = max(0, Int(referenceDate.timeIntervalSince(date)))
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) hr ago" }
        let days = hours / 24
        return days == 1 ? "1 day ago" : "\(days) days ago"
    }
}

@main
struct BoltBatteryWidget: Widget {
    let kind: String = "BoltBatteryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BoltBatteryProvider()) { entry in
            entryView(for: entry)
        }
        .configurationDisplayName("Bolt Battery")
        .description("Battery level for your Bolt-paired keyboard.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }

    @ViewBuilder
    private func entryView(for entry: BoltBatteryEntry) -> some View {
        if #available(macOS 14.0, *) {
            BoltBatteryWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    ZStack {
                        Color.black.opacity(0.18)
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(0.22), location: 0.0),
                                .init(color: Color.white.opacity(0.06), location: 0.45),
                                .init(color: Color.clear, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        LinearGradient(
                            stops: [
                                .init(color: Color.clear, location: 0.0),
                                .init(color: Color.black.opacity(0.10), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                }
        } else {
            BoltBatteryWidgetEntryView(entry: entry)
                .padding()
                .background(Color(nsColor: .windowBackgroundColor))
        }
    }
}

#if DEBUG
private func mockSnapshot(
    soc: Int,
    charging: String,
    sampledAt: Date = Date(),
    lastChargeEndedAt: Date? = nil,
    lastChargeEndedPercent: Int? = nil,
    lastError: String? = nil
) -> BatterySnapshot {
    BatterySnapshot(
        sampledAt: sampledAt,
        socPercent: soc,
        chargingState: charging,
        externalPower: charging.hasPrefix("charging"),
        deviceName: "MX Keys S",
        deviceType: "Keyboard",
        lastChargeEndedAt: lastChargeEndedAt,
        lastChargeEndedPercent: lastChargeEndedPercent,
        lastError: lastError,
        producerVersion: "0.1.0"
    )
}

@available(macOS 14.0, *)
#Preview("Discharging 75%", as: .systemSmall) {
    BoltBatteryWidget()
} timeline: {
    BoltBatteryEntry(
        date: Date(),
        snapshot: mockSnapshot(
            soc: 75,
            charging: "discharging",
            lastChargeEndedAt: Date(timeIntervalSinceNow: -6 * 60 * 60),
            lastChargeEndedPercent: 82
        )
    )
}

@available(macOS 14.0, *)
#Preview("Charging 15%", as: .systemSmall) {
    BoltBatteryWidget()
} timeline: {
    BoltBatteryEntry(date: Date(), snapshot: mockSnapshot(soc: 15, charging: "charging"))
}

@available(macOS 14.0, *)
#Preview("Charged 100%", as: .systemSmall) {
    BoltBatteryWidget()
} timeline: {
    BoltBatteryEntry(date: Date(), snapshot: mockSnapshot(soc: 100, charging: "charging-full"))
}

@available(macOS 14.0, *)
#Preview("Low 12%", as: .systemSmall) {
    BoltBatteryWidget()
} timeline: {
    BoltBatteryEntry(date: Date(), snapshot: mockSnapshot(soc: 12, charging: "discharging"))
}

@available(macOS 14.0, *)
#Preview("Missing Snapshot", as: .systemSmall) {
    BoltBatteryWidget()
} timeline: {
    BoltBatteryEntry(date: Date(), snapshot: nil)
}

@available(macOS 14.0, *)
#Preview("Stale Snapshot", as: .systemSmall) {
    BoltBatteryWidget()
} timeline: {
    let sampledAt = Date(timeIntervalSinceNow: -31 * 60)
    BoltBatteryEntry(
        date: Date(),
        snapshot: mockSnapshot(soc: 75, charging: "discharging", sampledAt: sampledAt)
    )
}

@available(macOS 14.0, *)
#Preview("Receiver Disconnected", as: .systemSmall) {
    BoltBatteryWidget()
} timeline: {
    BoltBatteryEntry(
        date: Date(),
        snapshot: mockSnapshot(soc: 75, charging: "discharging", lastError: "Receiver disconnected")
    )
}

@available(macOS 14.0, *)
#Preview("Keyboard Offline", as: .systemSmall) {
    BoltBatteryWidget()
} timeline: {
    BoltBatteryEntry(
        date: Date(),
        snapshot: mockSnapshot(soc: 75, charging: "discharging", lastError: "Keyboard offline")
    )
}

@available(macOS 14.0, *)
#Preview("HID++ Error", as: .systemSmall) {
    BoltBatteryWidget()
} timeline: {
    BoltBatteryEntry(
        date: Date(),
        snapshot: mockSnapshot(soc: 75, charging: "discharging", lastError: "Error: 0x08")
    )
}
#endif
