import Charts
import SwiftUI

struct BatteryView: View {
    @ObservedObject var engine: SamplingEngine
    @ObservedObject var processMonitor: ProcessMonitor
    @ObservedObject var preferences: Preferences
    @StateObject private var iconCache = ProcessIconCache()
    @State private var period = 0

    private var battery: BatteryIntelligence { engine.batteryIntelligence }
    private var points: [BatteryHistoryPoint] {
        guard period > 0 else { return battery.history }
        let cutoff = Date().addingTimeInterval(-Double(period * 60))
        return battery.history.filter { $0.date >= cutoff }
    }
    private var topProcesses: [ProcessRecord] {
        processMonitor.records.filter { $0.energyScore != nil }.sorted { ($0.energyScore ?? 0) > ($1.energyScore ?? 0) }.prefix(5).map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                currentSection
                healthSection
                liveEnergySection
                historySection
                energyProcessesSection
                insightsSection
                sourceSection
            }
            .padding(28)
            .frame(maxWidth: 1250, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { processMonitor.start(interval: preferences.processInterval) }
        .onDisappear { processMonitor.stop() }
        .onChange(of: preferences.processInterval) { _, value in processMonitor.restartIfNeeded(interval: value) }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("Battery")).font(.largeTitle.weight(.semibold))
                Text(L10n.text("What is happening with your battery right now?")).foregroundStyle(.secondary)
            }
            Spacer()
            Text(engine.snapshot.date, style: .time).font(.caption).monospacedDigit().foregroundStyle(.secondary).padding(.top, 10)
        }
    }

    private var currentSection: some View {
        HStack(alignment: .center, spacing: 24) {
            Image(systemName: "battery.75percent").font(.system(size: 52, weight: .medium)).foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 4) {
                Text(battery.level.map { String(format: "%.0f%%", locale: Locale.current, $0) } ?? "—")
                    .font(.system(size: 42, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(L10n.text(battery.state.titleKey)).font(.headline).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 7) {
                if battery.state == .discharging { estimateRow("Estimated Remaining", battery.estimatedRemainingHours) }
                else if battery.state == .charging { estimateRow("Time to Full", battery.timeToFullHours) }
                metricRow("Battery Power", power(battery.power))
                metricRow("Health", percent(battery.health))
                metricRow("Battery Temperature", temperature(battery.temperature))
            }
        }
        .padding(22)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.primary.opacity(0.06)))
        .accessibilityIdentifier("battery-current")
    }

    private var healthSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("Battery Health")).font(.title2.weight(.semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), alignment: .leading)], spacing: 12) {
                metricCard("Design Capacity", capacity(battery.designCapacity))
                metricCard("Full Charge Capacity", capacity(battery.fullChargeCapacity))
                metricCard("Current Capacity", capacity(battery.currentCapacity))
                metricCard("Cycle Count", count(battery.cycles))
                metricCard("Health", percent(battery.health))
            }
        }
    }

    private var liveEnergySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("Live Energy")).font(.title2.weight(.semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), alignment: .leading)], spacing: 12) {
                metricCard("Battery Power", power(battery.power))
                metricCard("Voltage", voltage(battery.voltage))
                metricCard("Current", amperage(battery.current))
                metricCard(battery.power.map { $0 >= 0 ? "Charge Rate" : "Discharge Rate" } ?? "Charge Rate", rate(battery.chargeRate))
                metricCard("Power Adapter", adapterPower)
                metricCard("Adapter Input Power", power(battery.adapterInputPower))
            }
            Text(L10n.text("Battery Power is battery flow. Adapter Rated Power is the adapter's capability. Adapter Input Power is measured input when available; neither is total SoC power.")).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.text("Battery History")).font(.title2.weight(.semibold))
                Spacer()
                Picker(L10n.text("History"), selection: $period) {
                    Text(L10n.text("5 min")).tag(5)
                    Text(L10n.text("15 min")).tag(15)
                    Text(L10n.text("30 min")).tag(30)
                    Text(L10n.text("1 h")).tag(60)
                    Text(L10n.text("3 h")).tag(180)
                    Text(L10n.text("Session")).tag(0)
                }.pickerStyle(.segmented).frame(width: 430)
            }
            if points.isEmpty {
                ContentUnavailableView(L10n.text("Calculating…"), systemImage: "chart.xyaxis.line", description: Text(L10n.text("More samples are needed for battery history."))).frame(height: 170)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14)], spacing: 14) {
                    BatteryLineChart(title: L10n.text("Battery Level"), unit: "%", series: points.compactMap { point in point.level.map { BatterySeriesPoint(date: point.date, value: $0) } }, domain: 0...100)
                    BatteryLineChart(title: L10n.text("Power"), unit: "W", series: points.compactMap { point in point.power.map { BatterySeriesPoint(date: point.date, value: $0) } })
                    BatteryLineChart(title: L10n.text("Battery Temperature"), unit: "°C", series: points.compactMap { point in point.temperature.map { BatterySeriesPoint(date: point.date, value: $0) } })
                    BatteryLineChart(title: L10n.text("Charge Rate"), unit: "%/h", series: points.compactMap { point in point.chargeRate.map { BatterySeriesPoint(date: point.date, value: $0) } })
                }
            }
        }
    }

    private var energyProcessesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("Top Energy Processes")).font(.title2.weight(.semibold))
            if topProcesses.isEmpty {
                Text(L10n.text("Energy process scores are calculating…")).font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(topProcesses) { record in
                        HStack(spacing: 10) {
                            Image(nsImage: iconCache.icon(for: record)).resizable().frame(width: 22, height: 22)
                            Text(record.name).lineLimit(1)
                            Spacer()
                            Text(L10n.format("PID %d", record.pid)).font(.caption).foregroundStyle(.secondary)
                            Text(score(record.energyScore)).font(.headline).monospacedDigit()
                        }.padding(.vertical, 8).overlay(alignment: .bottom) { Divider() }
                    }
                }
                .padding(.horizontal, 14)
                .background(.background, in: RoundedRectangle(cornerRadius: 12))
            }
            Text(L10n.text("MacPulse Energy Score is a relative activity score, not Apple's official Energy Impact.")).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text("Battery Insights")).font(.title2.weight(.semibold))
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: insightSymbol).font(.title2).foregroundStyle(insightColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text(battery.insight.titleKey)).font(.headline)
                    Text(L10n.text(battery.insight.detailKey)).foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.primary.opacity(0.06)))
        }
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L10n.text("Battery data source: IOKit Power Sources plus AppleSmartBattery registry details.")).font(.caption).foregroundStyle(.secondary)
            Text(L10n.text("Battery Power is signed: positive means charge, negative means discharge. System/SoC power is a separate metric.")).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var adapterPower: String {
        guard let watts = battery.adapterRatedPower else { return L10n.text("Unavailable") }
        return L10n.format("%.0f W · %@", watts, L10n.text("Connected"))
    }
    private var insightSymbol: String { switch battery.insight { case .batteryHot: "thermometer.sun"; case .highEnergyUsage: "bolt.trianglebadge.exclamationmark"; case .charging: "bolt.fill"; case .fullyCharged: "battery.100percent"; default: "checkmark.circle" } }
    private var insightColor: Color { switch battery.insight { case .batteryHot, .highEnergyUsage: .orange; case .charging, .fullyCharged: .green; default: .accentColor } }
    private func estimateRow(_ key: String, _ hours: Double?) -> some View { metricRow(key, hours.map(duration) ?? L10n.text("Calculating…")) }
    private func metricRow(_ key: String, _ value: String) -> some View { HStack(spacing: 8) { Text(L10n.text(key)).foregroundStyle(.secondary); Text(value).font(.headline).monospacedDigit() } }
    private func metricCard(_ key: String, _ value: String) -> some View { VStack(alignment: .leading, spacing: 6) { Text(L10n.text(key)).font(.caption).foregroundStyle(.secondary); Text(value).font(.headline).monospacedDigit() }.frame(maxWidth: .infinity, minHeight: 62, alignment: .leading).padding(14).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.primary.opacity(0.06))) }
    private func percent(_ value: Double?) -> String { value.map { String(format: "%.0f%%", locale: Locale.current, $0) } ?? "—" }
    private func power(_ value: Double?) -> String { value.map { String(format: "%+.1f W", locale: Locale.current, $0) } ?? "—" }
    private func capacity(_ value: Double?) -> String { value.map { String(format: "%.0f mAh", locale: Locale.current, $0) } ?? "—" }
    private func temperature(_ value: Double?) -> String { value.map { String(format: "%.1f °C", locale: Locale.current, $0) } ?? "—" }
    private func voltage(_ value: Double?) -> String { value.map { String(format: "%.2f V", locale: Locale.current, $0) } ?? "—" }
    private func amperage(_ value: Double?) -> String { value.map { String(format: "%+.2f A", locale: Locale.current, $0) } ?? "—" }
    private func rate(_ value: Double?) -> String { value.map { String(format: "%+.1f %%/h", locale: Locale.current, $0) } ?? "—" }
    private func count(_ value: Double?) -> String { value.map { String(format: "%.0f", locale: Locale.current, $0) } ?? "—" }
    private func score(_ value: Double?) -> String { value.map { String(format: "%.0f", locale: Locale.current, $0) } ?? "—" }
    private func duration(_ hours: Double) -> String { let minutes = Int((hours * 60).rounded()); return L10n.format("%d h %02d min", minutes / 60, minutes % 60) }
}

struct BatterySeriesPoint: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}

private struct BatteryLineChart: View {
    let title: String
    let unit: String
    let series: [BatterySeriesPoint]
    var domain: ClosedRange<Double>?
    init(title: String, unit: String, series: [BatterySeriesPoint], domain: ClosedRange<Double>? = nil) { self.title = title; self.unit = unit; self.series = series; self.domain = domain }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack { Text(title).font(.headline); Spacer(); Text(unit).font(.caption).foregroundStyle(.secondary) }
            Chart(series) { point in LineMark(x: .value("Time", point.date), y: .value(title, point.value)).foregroundStyle(Color.accentColor) }
                .chartYScale(domain: domain ?? automaticDomain).chartXAxis(.hidden).chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 2)) { AxisValueLabel() } }.frame(height: 115)
            Text(series.last.map { String(format: "%.1f %@", locale: Locale.current, $0.value, unit) } ?? "—").font(.caption2).monospacedDigit().foregroundStyle(.secondary)
        }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 12))
    }
    private var automaticDomain: ClosedRange<Double> { let values = series.map(\.value); let low = values.min() ?? 0; let high = values.max() ?? 1; let padding = max(0.5, (high - low) * 0.15); return (low - padding)...(high + padding) }
}
