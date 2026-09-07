import Charts
import SwiftUI

struct ProcessesView: View {
    @ObservedObject var monitor: ProcessMonitor
    @ObservedObject var preferences: Preferences
    @StateObject private var iconCache = ProcessIconCache()
    @State private var scope: ProcessScope = .user
    @State private var sort: ProcessSort = .cpu
    @State private var query = ""
    @State private var selectedPID: Int32?

    init(monitor: ProcessMonitor, preferences: Preferences) {
        self.monitor = monitor
        self.preferences = preferences
        _scope = State(initialValue: preferences.showSystemProcesses ? .all : .user)
    }

    private var filteredRecords: [ProcessRecord] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = monitor.records.filter { record in
            let scopeMatches = scope == .all || record.isUserProcess
            guard scopeMatches else { return false }
            guard !search.isEmpty else { return true }
            return record.name.lowercased().contains(search) || String(record.pid).contains(search)
        }
        let sorted = filtered.sorted { lhs, rhs in
            switch sort {
            case .cpu: return compare(lhs.cpuPercent, rhs.cpuPercent, lhs.name, rhs.name)
            case .memory: return compare(lhs.memoryBytes.map(Double.init), rhs.memoryBytes.map(Double.init), lhs.name, rhs.name)
            case .energy: return compare(lhs.energyScore, rhs.energyScore, lhs.name, rhs.name)
            case .network: return compare(lhs.networkTotalRate, rhs.networkTotalRate, lhs.name, rhs.name)
            case .disk: return compare(lhs.diskTotalRate, rhs.diskTotalRate, lhs.name, rhs.name)
            case .name: return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
        guard search.isEmpty, preferences.processTopLimit > 0 else { return sorted }
        return Array(sorted.prefix(preferences.processTopLimit))
    }

    private var selectedRecord: ProcessRecord? {
        guard let selectedPID else { return nil }
        return monitor.records.first { $0.pid == selectedPID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.text("Processes")).font(.largeTitle.weight(.semibold))
                    Text(L10n.text("See which processes are using your Mac right now.")).foregroundStyle(.secondary)
                }
                Spacer()
                Label(monitor.isSampling ? L10n.text("Live") : L10n.text("Paused"), systemImage: "circle.fill")
                    .font(.caption).foregroundStyle(monitor.isSampling ? .green : .secondary)
            }
            HStack(spacing: 12) {
                TextField(L10n.text("Search Processes"), text: $query)
                    .textFieldStyle(.roundedBorder).frame(minWidth: 220)
                    .accessibilityIdentifier("process-search")
                Picker(L10n.text("Show"), selection: $scope) {
                    ForEach(ProcessScope.allCases) { value in Text(L10n.text(value.titleKey)).tag(value) }
                }.pickerStyle(.segmented).frame(width: 250)
                Picker(L10n.text("Sort by"), selection: $sort) {
                    ForEach(ProcessSort.allCases) { value in Text(L10n.text(value.titleKey)).tag(value) }
                }.frame(width: 150).accessibilityIdentifier("process-sort")
            }
            HStack(spacing: 12) {
                Text(L10n.format("%@ processes", formattedCount(filteredRecords.count))).font(.caption).foregroundStyle(.secondary)
                if let updated = monitor.lastUpdated { Text(L10n.format("Updated %@", updated.formatted(date: .omitted, time: .standard))).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Text(L10n.format("Sampler: %.1f ms", monitor.sampleDurationMilliseconds)).font(.caption2).foregroundStyle(.tertiary)
            }
            if filteredRecords.isEmpty {
                ContentUnavailableView(L10n.text("No processes found"), systemImage: "list.bullet.rectangle", description: Text(L10n.text("Try another search or filter.")))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProcessTable(records: filteredRecords, selectedPID: $selectedPID, iconCache: iconCache)
                if let record = selectedRecord {
                    ProcessDetailPanel(record: record, history: monitor.history(for: record.pid), iconCache: iconCache)
                }
            }
            Text(L10n.text("Network per-process accounting is unavailable through public macOS APIs; no synthetic network values are shown."))
                .font(.caption).foregroundStyle(.secondary).padding(.top, 2)
        }
        .padding(28)
        .onAppear { monitor.start(interval: preferences.processInterval) }
        .onDisappear { monitor.stop() }
        .onChange(of: preferences.processInterval) { _, value in monitor.restartIfNeeded(interval: value) }
        .onChange(of: monitor.records) { _, records in
            if let selectedPID, !records.contains(where: { $0.pid == selectedPID }) { self.selectedPID = nil }
        }
    }

    private func compare<T: Comparable>(_ lhs: T?, _ rhs: T?, _ lhsName: String, _ rhsName: String) -> Bool {
        switch (lhs, rhs) {
        case let (left?, right?) where left != right: return left > right
        case (_?, nil): return true
        case (nil, _?): return false
        default: return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
        }
    }

    private func formattedCount(_ count: Int) -> String { String(count) }
}

private struct ProcessTable: View {
    let records: [ProcessRecord]
    @Binding var selectedPID: Int32?
    @ObservedObject var iconCache: ProcessIconCache

    var body: some View {
        VStack(spacing: 0) {
            ProcessTableHeader()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(records) { record in
                        Button { selectedPID = record.pid } label: {
                            ProcessRow(record: record, iconCache: iconCache)
                        }
                        .buttonStyle(.plain)
                        .background(selectedPID == record.pid ? Color.accentColor.opacity(0.14) : .clear)
                        .overlay(alignment: .bottom) { Divider() }
                        .accessibilityIdentifier("process-\(record.pid)")
                    }
                }
            }.frame(minHeight: 180, maxHeight: 340)
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.primary.opacity(0.08)))
    }
}

private struct ProcessTableHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            Text(L10n.text("Process")).frame(width: 210, alignment: .leading)
            Text(L10n.text("CPU")).frame(width: 70, alignment: .trailing)
            Text(L10n.text("Memory")).frame(width: 90, alignment: .trailing)
            Text(L10n.text("Energy Score")).frame(width: 90, alignment: .trailing)
            Text("↓").frame(width: 72, alignment: .trailing).help(L10n.text("Network download unavailable"))
            Text("↑").frame(width: 72, alignment: .trailing).help(L10n.text("Network upload unavailable"))
            Text("R").frame(width: 72, alignment: .trailing).help(L10n.text("Disk read"))
            Text("W").frame(width: 72, alignment: .trailing).help(L10n.text("Disk write"))
        }
        .font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.vertical, 10)
    }
}

private struct ProcessRow: View {
    let record: ProcessRecord
    @ObservedObject var iconCache: ProcessIconCache

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 9) {
                Image(nsImage: iconCache.icon(for: record)).resizable().frame(width: 20, height: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.name).lineLimit(1)
                    Text(L10n.format("PID %d", record.pid)).font(.caption2).foregroundStyle(.secondary)
                }
            }.frame(width: 210, alignment: .leading)
            Text(percent(record.cpuPercent)).frame(width: 70, alignment: .trailing)
            Text(bytes(record.memoryBytes)).frame(width: 90, alignment: .trailing)
            Text(score(record.energyScore)).frame(width: 90, alignment: .trailing)
            Text(rate(record.networkDownload)).frame(width: 72, alignment: .trailing)
            Text(rate(record.networkUpload)).frame(width: 72, alignment: .trailing)
            Text(rate(record.diskReadRate)).frame(width: 72, alignment: .trailing)
            Text(rate(record.diskWriteRate)).frame(width: 72, alignment: .trailing)
        }
        .font(.system(.body, design: .monospaced)).monospacedDigit().padding(.horizontal, 12).padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}

private struct ProcessDetailPanel: View {
    let record: ProcessRecord
    let history: [ProcessHistoryPoint]
    @ObservedObject var iconCache: ProcessIconCache

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: iconCache.icon(for: record)).resizable().frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(record.name).font(.title3.weight(.semibold))
                    Text(L10n.format("PID %d", record.pid)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], spacing: 10) {
                detailMetric(L10n.text("CPU"), percent(record.cpuPercent))
                detailMetric(L10n.text("Memory"), bytes(record.memoryBytes))
                detailMetric(L10n.text("Energy Score"), score(record.energyScore))
                detailMetric(L10n.text("Network"), L10n.text("Unavailable"))
                detailMetric(L10n.text("Disk read"), rate(record.diskReadRate))
                detailMetric(L10n.text("Disk write"), rate(record.diskWriteRate))
            }
            if let bundle = record.bundleIdentifier { detailLine(L10n.text("Bundle identifier"), bundle) }
            if let path = record.executablePath { detailLine(L10n.text("Executable"), path) }
            detailLine(L10n.text("Parent PID"), String(record.parentPID))
            if let threads = record.threadCount { detailLine(L10n.text("Threads"), String(threads)) }
            if !history.isEmpty {
                HStack(spacing: 14) {
                    ProcessMiniChart(title: L10n.text("CPU"), points: history.compactMap { $0.cpuPercent })
                    ProcessMiniChart(title: L10n.text("Memory"), points: history.compactMap { $0.memoryBytes.map(Double.init) }, formatter: { bytes(UInt64(max(0, $0))) })
                }.frame(height: 120)
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("process-detail-\(record.pid)")
    }

    private func detailMetric(_ name: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) { Text(name).font(.caption).foregroundStyle(.secondary); Text(value).font(.headline).monospacedDigit() }
    }
    private func detailLine(_ name: String, _ value: String) -> some View {
        HStack { Text(name).foregroundStyle(.secondary); Spacer(); Text(value).textSelection(.enabled).lineLimit(1) }.font(.caption)
    }
}

private struct ProcessMiniChart: View {
    let title: String
    let points: [Double]
    var formatter: (Double) -> String = { String(format: "%.0f", locale: Locale.current, $0) }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Chart(Array(points.enumerated()), id: \.offset) { index, value in
                LineMark(x: .value("Sample", index), y: .value(title, value)).foregroundStyle(Color.accentColor)
            }.chartXAxis(.hidden).chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 2)) { AxisValueLabel() } }
            Text(points.last.map(formatter) ?? "—").font(.caption2).monospacedDigit().foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func percent(_ value: Double?) -> String {
    guard let value, value.isFinite else { return "—" }
    return String(format: "%.1f%%", locale: Locale.current, value)
}

private func score(_ value: Double?) -> String {
    guard let value, value.isFinite else { return "—" }
    return String(format: "%.0f", locale: Locale.current, value)
}

private func bytes(_ value: UInt64?) -> String {
    guard let value else { return "—" }
    return ByteCountFormatter.string(fromByteCount: Int64(min(value, UInt64(Int64.max))), countStyle: .binary)
}

private func rate(_ value: Double?) -> String {
    guard let value, value.isFinite else { return "—" }
    return ByteCountFormatter.string(fromByteCount: Int64(min(value, Double(Int64.max))), countStyle: .binary) + "/s"
}
