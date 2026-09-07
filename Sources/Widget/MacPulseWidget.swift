import SwiftUI
import WidgetKit

struct PulseEntry: TimelineEntry { let date: Date; let snapshot: WidgetSnapshot? }
struct PulseProvider: TimelineProvider {
    func placeholder(in context: Context) -> PulseEntry { PulseEntry(date: .now, snapshot: nil) }
    func getSnapshot(in context: Context, completion: @escaping (PulseEntry) -> Void) { completion(PulseEntry(date: .now, snapshot: WidgetSnapshot.read())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PulseEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetSnapshot.read()
        let entries = [PulseEntry(date: now, snapshot: snapshot), PulseEntry(date: now.addingTimeInterval(900), snapshot: snapshot)]
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(900))))
    }
}
struct PulseWidgetView: View {
    var entry: PulseEntry
    @Environment(\.widgetFamily) private var family
    private var stale: Bool { guard let snapshot = entry.snapshot else { return true }; return entry.date.timeIntervalSince(snapshot.date)>900 }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("MacPulse", systemImage: "waveform.path.ecg").font(.headline)
            if let snapshot = entry.snapshot {
                HStack(spacing: 20) { reading("CPU", snapshot.cpu, "%"); reading("RAM", snapshot.memory, "%"); if family == .systemMedium { reading("Battery", snapshot.battery, "%"); reading("CPU temp", snapshot.temperature, "°C") } }
                Spacer(minLength: 0)
                HStack(spacing: 4) { Text(stale ? "Last reading" : "Updated"); Text(snapshot.date, style: .time) }.font(.caption2).foregroundStyle(.secondary)
                if stale { Text("Open MacPulse to refresh").font(.caption2).foregroundStyle(.secondary) }
            } else {
                Text("Open MacPulse to share real system readings.").font(.caption).foregroundStyle(.secondary)
            }
        }.containerBackground(.background, for: .widget)
    }
    private func reading(_ name: String, _ value: Double?, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(name).font(.caption).foregroundStyle(.secondary); Text(value.map { String(format:"%.0f",$0)+unit } ?? "—").font(.system(size: 23, weight: .medium, design: .rounded)).minimumScaleFactor(0.7).lineLimit(1) }
    }
}
@main struct MacPulseWidget: Widget {
    let kind = "MacPulseWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PulseProvider()) { PulseWidgetView(entry: $0) }
            .configurationDisplayName("MacPulse").description("A timestamped snapshot of your Mac's CPU, memory and battery.").supportedFamilies([.systemSmall,.systemMedium])
    }
}
