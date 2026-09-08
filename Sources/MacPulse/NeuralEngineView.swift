import Charts
import SwiftUI

struct NeuralEngineView: View {
    @ObservedObject var engine: SamplingEngine
    @State private var period = 5

    private var ane: ANEIntelligence { engine.aneIntelligence }
    private var points: [ANEHistoryPoint] {
        guard period > 0 else { return ane.history }
        let cutoff = Date().addingTimeInterval(-Double(period * 60))
        return ane.history.filter { $0.date >= cutoff }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                heading
                current
                summary
                history
                semantics
            }
            .padding(28)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("neural-engine-page")
    }

    private var heading: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("Neural Engine")).font(.largeTitle.weight(.semibold))
                Text(L10n.text("Apple Neural Engine activity and modeled power.")).foregroundStyle(.secondary)
            }
            Spacer()
            Text(engine.snapshot.date, style: .time).font(.caption).monospacedDigit().foregroundStyle(.secondary).padding(.top, 10)
        }
    }

    private var current: some View {
        HStack(spacing: 18) {
            Image(systemName: ane.state == .active ? "bolt.fill" : "bolt.horizontal").font(.system(size: 42, weight: .medium)).foregroundStyle(ane.state == .active ? .orange : .secondary)
            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.text(ane.state.titleKey)).font(.title2.weight(.semibold))
                Text(L10n.text("ANE activity is inferred from the power channel; utilization percentage is unavailable."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: 520, alignment: .leading)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(L10n.text("ANE Power")).font(.caption).foregroundStyle(.secondary)
                Text(power(ane.power)).font(.system(size: 32, weight: .semibold, design: .rounded)).monospacedDigit()
            }
        }
        .padding(22)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.primary.opacity(0.06)))
        .accessibilityIdentifier("ane-current")
    }

    private var summary: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), alignment: .leading)], spacing: 12) {
            valueCard("Activity", L10n.text(ane.state.titleKey))
            valueCard("ANE Power", power(ane.power))
            valueCard("Recent Average", power(ane.recentAverage))
            valueCard("Session Peak", power(ane.peak))
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.text("ANE History")).font(.title2.weight(.semibold))
                Spacer()
                Picker(L10n.text("History"), selection: $period) {
                    Text(L10n.text("5 min")).tag(5)
                    Text(L10n.text("15 min")).tag(15)
                    Text(L10n.text("30 min")).tag(30)
                    Text(L10n.text("Session")).tag(0)
                }
                .pickerStyle(.segmented)
                .frame(width: 310)
            }
            let chartPoints = points.compactMap { point in point.power.map { ANEChartPoint(date: point.date, value: $0) } }
            if chartPoints.isEmpty {
                ContentUnavailableView(L10n.text("No readings yet"), systemImage: "bolt.horizontal", description: Text(L10n.text("A chart appears when ANE power becomes available."))).frame(height: 170)
            } else {
                Chart(chartPoints) { point in
                    AreaMark(x: .value(L10n.text("Time"), point.date), y: .value(L10n.text("ANE Power"), point.value)).foregroundStyle(Color.orange.opacity(0.16))
                    LineMark(x: .value(L10n.text("Time"), point.date), y: .value(L10n.text("ANE Power"), point.value)).foregroundStyle(.orange).lineStyle(StrokeStyle(lineWidth: 1.8))
                }
                .chartYScale(domain: 0...max(1, (chartPoints.map(\.value).max() ?? 1) * 1.15))
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { AxisValueLabel(format: .dateTime.hour().minute()); AxisGridLine() } }
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
                .frame(height: 190)
                .accessibilityLabel(L10n.format("%@ history, %d samples", L10n.text("ANE Power"), chartPoints.count))
            }
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
    }

    private var semantics: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.text("Source: private IOReport PMP channel named ANE, unit mJ.")).font(.caption).foregroundStyle(.secondary)
            Text(L10n.text("ANE Power is energy delta divided by elapsed time. It is a modeled rail estimate, not total SoC power.")).font(.caption).foregroundStyle(.secondary)
            Text(L10n.text("Utilization %, frequency and workload attribution are unavailable from this source.")).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func valueCard(_ key: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.text(key)).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).monospacedDigit()
        }
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.primary.opacity(0.06)))
    }

    private func power(_ value: Double?) -> String {
        value.map { String(format: "%.2f W", locale: Locale.current, $0) } ?? "—"
    }
}

private struct ANEChartPoint: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}
