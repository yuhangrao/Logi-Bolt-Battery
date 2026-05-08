import WidgetKit
import SwiftUI

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
        let entry = BoltBatteryEntry(date: Date(), snapshot: SnapshotStore.shared.read())
        completion(Timeline(entries: [entry], policy: .never))
    }
}

private struct BatteryRing: View {
    let socPercent: Int?
    let isCharging: Bool
    let glyphSymbolName: String

    private let lineWidth: CGFloat = 6.5

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.22), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: ringFraction)
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
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.yellow)
                    .padding(2)
                    .background(
                        Circle().fill(Color(nsColor: .windowBackgroundColor))
                    )
                    .offset(x: 13, y: 13)
            }
        }
    }

    private var ringFraction: CGFloat {
        guard let s = socPercent else { return 0 }
        return max(0, min(1, CGFloat(s) / 100.0))
    }

    private var ringColor: Color {
        if isCharging { return .green }
        guard let s = socPercent else { return .gray }
        return s <= 20 ? .red : .green
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

            ZStack(alignment: .topLeading) {
                BatteryRing(
                    socPercent: entry.snapshot?.socPercent,
                    isCharging: isCharging,
                    glyphSymbolName: "keyboard"
                )
                .frame(width: ringDiameter, height: ringDiameter)
                .position(x: ringCenterX, y: topRowCenterY)

                Text(percentText)
                    .font(.system(size: 31, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .fixedSize()
                    .position(x: percentCenterX, y: topRowCenterY)

                Text("Charge to start tracking")
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

    private var isCharging: Bool {
        guard let state = entry.snapshot?.chargingState.lowercased() else { return false }
        return state.hasPrefix("charging")
    }

    private var percentText: String {
        guard let soc = entry.snapshot?.socPercent else { return "—%" }
        return "\(soc)%"
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
private func mockSnapshot(soc: Int, charging: String) -> BatterySnapshot {
    BatterySnapshot(
        sampledAt: Date(),
        socPercent: soc,
        chargingState: charging,
        externalPower: charging.hasPrefix("charging"),
        deviceName: "MX Keys S",
        deviceType: "Keyboard",
        producerVersion: "0.1.0"
    )
}

@available(macOS 14.0, *)
#Preview("Discharging 75%", as: .systemSmall) {
    BoltBatteryWidget()
} timeline: {
    BoltBatteryEntry(date: Date(), snapshot: mockSnapshot(soc: 75, charging: "discharging"))
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
#endif
