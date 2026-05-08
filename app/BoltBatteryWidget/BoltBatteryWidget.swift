import WidgetKit
import SwiftUI

struct BoltBatteryEntry: TimelineEntry {
    let date: Date
    let snapshot: BatterySnapshot?

    static let placeholder = BoltBatteryEntry(
        date: Date(),
        snapshot: BatterySnapshot(
            sampledAt: Date(),
            socPercent: 35,
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

struct BoltBatteryWidgetEntryView: View {
    let entry: BoltBatteryEntry

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: ringFraction)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(percentText)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .frame(width: 76, height: 76)
            Text(entry.snapshot?.deviceName ?? "No data")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var ringFraction: CGFloat {
        guard let soc = entry.snapshot?.socPercent else { return 0 }
        return max(0, min(1, CGFloat(soc) / 100.0))
    }

    private var ringColor: Color {
        guard let soc = entry.snapshot?.socPercent else { return .secondary }
        if soc <= 20 { return .red }
        if soc <= 50 { return .yellow }
        return .green
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
    }

    @ViewBuilder
    private func entryView(for entry: BoltBatteryEntry) -> some View {
        if #available(macOS 14.0, *) {
            BoltBatteryWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        } else {
            BoltBatteryWidgetEntryView(entry: entry)
                .padding()
                .background(Color(nsColor: .windowBackgroundColor))
        }
    }
}
