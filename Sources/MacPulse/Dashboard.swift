import SwiftUI
import Charts

// Разделы описывают навигацию, не обращаясь к системным API.
enum SectionPage: String, CaseIterable, Identifiable {
    case overview = "Overview", cpu = "CPU", gpu = "GPU", memory = "Memory", thermals = "Thermals", battery = "Battery", power = "Power", network = "Network", storage = "Storage", system = "System", processes = "Processes"
    var id: String { rawValue }
    var displayName: String { L10n.text("page.\(rawValue)") }
    var symbol: String { switch self {
        case .overview: "square.grid.2x2"; case .cpu: "cpu"; case .gpu: "square.3.layers.3d"; case .memory: "memorychip"; case .thermals: "thermometer.medium"; case .battery: "battery.75percent"; case .power: "bolt"; case .network: "network"; case .storage: "internaldrive"; case .system: "laptopcomputer"; case .processes: "list.bullet.rectangle"
    } }
    var metrics: [Metric] { switch self {
        case .overview: [.cpu,.memory,.cpuTemperature,.battery,.download,.upload,.cpuPower,.storage]
        case .cpu: [.cpu,.cpuTemperature,.cpuPower]
        case .gpu: [.gpu,.gpuTemperature,.gpuPower,.gpuMemory]
        case .memory: [.memory,.memoryUsed,.memoryAvailable,.memoryTotal,.wired,.compressed,.cached,.swap,.swapTotal]
        case .thermals: [.cpuTemperature,.gpuTemperature,.batteryTemperature]
        case .battery: [.battery,.batteryHealth,.batteryPower,.batteryTemperature,.cycles,.voltage,.amperage,.currentCapacity,.maxCapacity,.designCapacity]
        case .power: [.cpuPower,.gpuPower,.anePower,.computePower,.systemPower,.packagePower,.batteryPower]
        case .network: [.download,.upload,.wifiSignal,.wifiNoise,.wifiLink]
        case .storage: [.storage,.storageAvailable,.storageUsed,.storageTotal,.diskRead,.diskWrite]
        case .system: []
        case .processes: []
    } }
    var charts: [Metric] { switch self {
        case .overview: [.cpu,.memory]
        case .cpu: [.cpu,.cpuTemperature,.cpuPower]
        case .gpu: [.gpu,.gpuPower]
        case .memory: [.memory,.swap]
        case .thermals: [.cpuTemperature,.gpuTemperature]
        case .battery: [.battery,.batteryPower]
        case .power: [.cpuPower,.gpuPower,.systemPower]
        case .network: [.download,.upload]
        case .storage: [.diskRead,.diskWrite]
        case .system: []
        case .processes: []
    } }
    var subtitle: String { switch self {
        case .overview: L10n.text("subtitle.overview")
        case .cpu: L10n.text("subtitle.cpu")
        case .gpu: L10n.text("subtitle.gpu")
        case .memory: L10n.text("subtitle.memory")
        case .thermals: L10n.text("subtitle.thermals")
        case .battery: L10n.text("subtitle.battery")
        case .power: L10n.text("subtitle.power")
        case .network: L10n.text("subtitle.network")
        case .storage: L10n.text("subtitle.storage")
        case .system: L10n.text("subtitle.system")
        case .processes: L10n.text("subtitle.processes")
    } }
}

struct MetricCard: View {
    let metric: Metric
    let snapshot: Snapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(metric.title, systemImage: metric.symbol).font(.subheadline).foregroundStyle(.secondary)
            Text(metric.format(snapshot[metric])).font(.system(size: 27, weight: .medium, design: .rounded)).monospacedDigit().contentTransition(.numericText())
            if snapshot[metric] == nil { Text("Unavailable").font(.caption).foregroundStyle(.secondary) }
            else if metric == .memory { Text(L10n.format("Pressure: %@", snapshot.pressureLabel)).font(.caption).foregroundStyle(.secondary) }
            else if metric == .battery { Text(snapshot.batteryState).font(.caption).foregroundStyle(.secondary) }
            else if metric == .storage { Text(L10n.format("%@ free", Metric.storageAvailable.format(snapshot[.storageAvailable]))).font(.caption).foregroundStyle(.secondary) }
            else if metric == .cpuTemperature || metric == .gpuTemperature { Text("Reported sensor average").font(.caption).foregroundStyle(.secondary) }
            else { Text(metric == .batteryPower ? L10n.text("Battery controller reading") : metric == .systemPower || metric == .packagePower ? L10n.text("Experimental SMC reading") : metric.unit == "W" ? L10n.text("Interval average") : L10n.text("Live reading")).font(.caption).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading).padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.primary.opacity(0.06)))
        .help(snapshot[metric] == nil ? snapshot.reason(for: metric) : metric.source)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("metric-\(metric.rawValue)")
    }
}
struct MetricChart: View {
    let metric: Metric
    let points: [HistoryPoint]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text(metric.title).font(.headline); Spacer(); Text(metric.unit).foregroundStyle(.secondary).font(.caption) }
            if points.contains(where: { $0.values[metric.rawValue] != nil }) {
                Chart {
                    ForEach(series) { point in
                            LineMark(x: .value(L10n.text("Time"), point.date), y: .value(metric.title, point.value), series: .value("segment", point.segment))
                            .foregroundStyle(Color.accentColor).lineStyle(StrokeStyle(lineWidth: 1.6))
                    }
                }
                .chartYScale(domain: chartDomain)
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { AxisValueLabel(format: .dateTime.hour().minute()); AxisGridLine() } }
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
                .frame(height: 130)
                .accessibilityLabel(L10n.format("%@ history, %d samples", metric.title, points.count))
            } else {
                ContentUnavailableView(L10n.text("No readings yet"), systemImage: metric.symbol, description: Text(L10n.text("A chart appears when this metric becomes available."))).frame(height: 130)
            }
        }.padding(18).background(.background, in: RoundedRectangle(cornerRadius: 14))
    }
    private var chartDomain: ClosedRange<Double> {
        let values = points.compactMap { $0.values[metric.rawValue] }
        return metric.unit == "%" ? 0...100 : min(0, values.min() ?? 0)...max(1, (values.max() ?? 1) * 1.1)
    }
    private struct ChartPoint: Identifiable { let date: Date; let value: Double; let segment: Int; var id: Date { date } }
    private var series: [ChartPoint] {
        var result: [ChartPoint] = [], segment = 0
        let step = max(1, points.count / 180)
        for (index, point) in points.enumerated() {
            if index > 0 && point.date.timeIntervalSince(points[index-1].date) > 15 { segment += 1 }
            guard let value = point.values[metric.rawValue] else { segment += 1; continue }
            if index % step == 0 || index == points.count-1 { result.append(ChartPoint(date: point.date, value: value, segment: segment)) }
        }
        return result
    }
}
struct DashboardView: View {
    @ObservedObject var engine: SamplingEngine
    @ObservedObject var preferences: Preferences
    @ObservedObject var processMonitor: ProcessMonitor
    @State private var selection: SectionPage? = .overview
    @State private var historyMinutes = 5
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                Label("MacPulse", systemImage: "waveform.path.ecg").font(.title3.weight(.semibold)).padding(20)
                List(SectionPage.allCases, selection: $selection) { page in
                    Label(page.displayName, systemImage: page.symbol).tag(page).padding(.vertical, 4).accessibilityIdentifier("nav-\(page.rawValue)")
                }.listStyle(.sidebar)
                VStack(alignment: .leading, spacing: 5) {
                    Text(engine.snapshot.info["chip"] ?? "Connecting…").font(.caption.weight(.semibold))
                    Label(engine.paused ? L10n.text("Paused during sleep") : L10n.format("Live · every %ds", Int(preferences.interval)), systemImage: "circle.fill").font(.caption2).foregroundStyle(.secondary)
                }.padding(20)
            }.navigationSplitViewColumnWidth(min: 175, ideal: 195, max: 225)
        } detail: {
            let page = selection ?? .overview
            if page == .processes {
                ProcessesView(monitor: processMonitor, preferences: preferences)
                    .background(Color(nsColor: .windowBackgroundColor))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 6) { Text(page.displayName).font(.largeTitle.weight(.semibold)); Text(page.subtitle).foregroundStyle(.secondary) }
                            Spacer()
                            Text(engine.snapshot.date, style: .time).font(.caption).monospacedDigit().foregroundStyle(.secondary).padding(.top, 10)
                        }
                        if page == .overview { statusStrip }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: page == .overview ? 170 : 210), spacing: 14)], spacing: 14) {
                            ForEach(page.metrics) { MetricCard(metric: $0, snapshot: engine.snapshot) }
                        }
                        details(page)
                        if !page.charts.isEmpty {
                            HStack { Text(L10n.text("Recent history")).font(.title3.weight(.semibold)); Spacer(); Picker(L10n.text("History"), selection: $historyMinutes) { Text(L10n.text("5 min")).tag(5); Text(L10n.text("15 min")).tag(15); Text(L10n.text("30 min")).tag(30) }.pickerStyle(.segmented).frame(width: 230) }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14)], spacing: 14) {
                                ForEach(page.charts) { MetricChart(metric: $0, points: chartPoints) }
                            }
                            Text(L10n.text("This session · up to 900 samples / 30 minutes · gaps remain visible")).font(.caption).foregroundStyle(.secondary)
                        }
                        if page != .overview && page != .system { sourceDetails(page) }
                    }.padding(28).frame(maxWidth: 1250, alignment: .leading).frame(maxWidth: .infinity)
                }.background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .toolbar { ToolbarItem { Button { openSettings() } label: { Image(systemName: "gearshape") }.help("Settings").accessibilityIdentifier("open-settings") } }
        .frame(minWidth: 860, minHeight: 620)
        .preferredColorScheme(preferences.colorScheme)
    }
    private var chartPoints: [HistoryPoint] {
        let filtered = engine.history.points.filter { $0.date > engine.snapshot.date.addingTimeInterval(Double(-historyMinutes*60)) }
        return filtered
    }
    private var statusStrip: some View {
        HStack(spacing: 24) {
            Label(L10n.format("Thermals: %@", engine.snapshot.thermalLabel), systemImage: "thermometer.medium")
            Label(L10n.format("Memory: %@", engine.snapshot.pressureLabel), systemImage: "memorychip")
            Spacer()
            Text(L10n.text(engine.snapshot.info["interface"] ?? "Connecting…"))
        }.font(.callout).foregroundStyle(.secondary).padding(16).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }
    @ViewBuilder private func details(_ page: SectionPage) -> some View {
        let s = engine.snapshot
        switch page {
        case .cpu:
            GroupBox(L10n.format("Logical cores · %@", L10n.text(s.info["cpuClusters"] ?? "Loading topology…"))) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 14) {
                    ForEach(Array(s.cores.enumerated()), id: \.offset) { i, value in
                        VStack(alignment: .leading) { HStack { Text(L10n.format("Core %d", i + 1)); Spacer(); Text(String(format: "%.0f%%", locale: Locale.current, value)).monospacedDigit() }; ProgressView(value: value, total: 100) }.font(.caption).padding(8)
                    }
                }.padding(8)
            }
            Text("Core indices come from Mach. Cluster counts come from sysctl; no unverified P/E labels are assigned to individual cores.").font(.caption).foregroundStyle(.secondary)
        case .memory:
            Text("Used = active + inactive + speculative + wired + compressed − purgeable − file-backed pages. Available = physical − used. Memory pressure is reported by macOS, independently of the usage percentage.").font(.callout).foregroundStyle(.secondary)
        case .thermals:
            GroupBox(L10n.format("Available temperature sensors · %d", s.sensors.count)) {
                VStack(spacing: 0) { ForEach(s.sensors.keys.sorted(), id: \.self) { name in valueRow(name, String(format: "%.1f°C", locale: Locale.current, s.sensors[name]!), localizedName: false) } }.padding(8)
            }
            Text("Private IOHID readings are reported as supplied by macOS. Inactive domains may stay at a 30°C floor. Negative and implausible readings are excluded. These are sensor readings, not a calibrated external thermometer.").font(.caption).foregroundStyle(.secondary)
        case .power:
            Text("CPU and GPU are modeled power from energy counters, not wall-socket measurements. The component sum is shown only when CPU, GPU and ANE are all available; it is never labeled total Mac power. SMC PSTR is the reported system rail; PHPC is exposed under its raw key because its package boundary is undocumented. Neither is a wall-socket measurement. Battery power is signed: negative means discharge.").font(.callout).foregroundStyle(.secondary)
            if s[.anePower] == nil { Label("ANE: no matching energy channel exposed by this macOS installation.", systemImage: "info.circle").font(.callout).foregroundStyle(.secondary) }
        case .network:
            GroupBox(L10n.text("Connection")) { VStack { valueRow("Primary interface", L10n.text(s.info["interface"] ?? "—")); valueRow("Local IPv4", L10n.text(s.info["localIP"] ?? "—")); valueRow("Wi-Fi network", L10n.text(s.info["wifiSSID"] ?? "Unavailable")) }.padding(8) }
            Text("Rates count the primary interface once. A route change starts a new interval. macOS can restrict the Wi-Fi name; MacPulse does not request location access.").font(.caption).foregroundStyle(.secondary)
        case .storage:
            GroupBox(L10n.text("Mounted volumes")) { VStack { ForEach(s.volumes) { v in valueRow(v.name, L10n.format("%@ free of %@", Metric.storageAvailable.format(v.available), Metric.storageTotal.format(v.total)), localizedName: false) } }.padding(8) }
            Text("Capacity uses immediately available space, excluding purgeable files. APFS volumes may share a container; their capacities must not be added. Read/write activity covers physical drives together.").font(.caption).foregroundStyle(.secondary)
        case .battery:
            let batteryAgeText = s.values["batteryAge"].map { L10n.format("Battery controller snapshot: %d seconds old.", Int($0)) } ?? L10n.text("Controller timestamp unavailable.")
            Text(batteryAgeText + " " + L10n.text("Health is full charge capacity / design capacity; it can differ from the rounded macOS battery-health estimate. Electrical values describe the battery, not charger input or total system power.")).font(.callout).foregroundStyle(.secondary)
        case .system:
            GroupBox(L10n.text("This Mac")) { VStack { valueRow("Model", s.info["model"] ?? "—"); valueRow("Chip", s.info["chip"] ?? "—"); valueRow("macOS", s.info["os"] ?? "—"); valueRow("Hostname", s.info["hostname"] ?? "—"); valueRow("Uptime", uptime(s.values["uptime"])); valueRow("Physical memory", Metric.memoryTotal.format(s[.memoryTotal])); valueRow("Sampling cost", L10n.format("%.1f ms / sample", engine.samplingMilliseconds)); valueRow("Widget sharing", engine.widgetStatus) }.padding(8) }
            GroupBox(L10n.text("Local by design")) { Text(L10n.text("No accounts, backend, telemetry or analytics. History stays in memory and is cleared on quit. Only a small timestamped summary is shared with the widget on this Mac.")).frame(maxWidth: .infinity, alignment: .leading).padding(12) }
        default: EmptyView()
        }
    }
    private func sourceDetails(_ page: SectionPage) -> some View {
        DisclosureGroup("Sources & availability") {
            VStack(alignment: .leading, spacing: 12) { ForEach(page.metrics) { metric in
            VStack(alignment: .leading, spacing: 3) { Text(metric.title).fontWeight(.medium); Text(metric.source).foregroundStyle(.secondary); if engine.snapshot[metric] == nil { Text(engine.snapshot.reason(for: metric)).foregroundStyle(.secondary) } }.font(.caption)
            } }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
        }
    }
    private func valueRow(_ name: String, _ value: String, localizedName: Bool = true) -> some View { HStack { Text(localizedName ? L10n.text(name) : name).foregroundStyle(.secondary); Spacer(); Text(value).monospacedDigit().textSelection(.enabled) }.padding(.vertical, 7) }
    private func uptime(_ seconds: Double?) -> String { guard let seconds else { return "—" }; return L10n.format("%dd %dh %dm", Int(seconds)/86400, Int(seconds)/3600%24, Int(seconds)/60%60) }
}
