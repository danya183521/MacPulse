import Foundation

enum HealthCategory: String, CaseIterable, Codable, Identifiable {
    case compute
    case memory
    case thermals
    case battery
    case storage

    var id: String { rawValue }
    var title: String { L10n.text("health.category.\(rawValue)") }
    var symbol: String {
        switch self {
        case .compute: "cpu"
        case .memory: "memorychip"
        case .thermals: "thermometer.medium"
        case .battery: "battery.75percent"
        case .storage: "internaldrive"
        }
    }
}

enum HealthSeverity: Int, Codable, Comparable {
    case unavailable = -1
    case excellent = 0
    case normal = 1
    case elevated = 2
    case high = 3
    case critical = 4

    static func < (lhs: HealthSeverity, rhs: HealthSeverity) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .unavailable: L10n.text("Unavailable")
        case .excellent: L10n.text("health.severity.excellent")
        case .normal: L10n.text("health.severity.normal")
        case .elevated: L10n.text("health.severity.elevated")
        case .high: L10n.text("health.severity.high")
        case .critical: L10n.text("health.severity.critical")
        }
    }

    static func score(_ score: Int, available: Bool = true) -> HealthSeverity {
        guard available else { return .unavailable }
        switch score {
        case 90...100: return .excellent
        case 75..<90: return .normal
        case 55..<75: return .elevated
        case 30..<55: return .high
        default: return .critical
        }
    }
}

enum HealthTrend: String, Codable {
    case rising
    case stable
    case falling
    case unavailable

    var title: String { L10n.text("health.trend.\(rawValue)") }
}

enum HealthConfidence: String, Codable {
    case high
    case medium
    case low

    var title: String { L10n.text("health.confidence.\(rawValue)") }
}

enum HealthBaselineState: Equatable, Codable {
    case learning(samples: Int)
    case ready(samples: Int)

    var title: String {
        switch self {
        case .learning: L10n.text("health.baseline.learning")
        case .ready: L10n.text("health.baseline.ready")
        }
    }

    var samples: Int {
        switch self {
        case .learning(let samples), .ready(let samples): samples
        }
    }
}

struct HealthEvidence: Identifiable, Equatable {
    let id: String
    let label: String
    let value: String
    let detail: String?
}

struct HealthRootCause: Equatable {
    let processID: Int32?
    let name: String
    let confidence: HealthConfidence
    let role: String
    let evidence: [HealthEvidence]
}

struct HealthRecommendation: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
}

struct HealthIssue: Identifiable, Equatable {
    let id: String
    let category: HealthCategory
    let severity: HealthSeverity
    let title: String
    let summary: String
    let duration: TimeInterval
    let penalty: Int
    let evidence: [HealthEvidence]
    let rootCause: HealthRootCause?
    let recommendation: HealthRecommendation?
}

struct HealthCategorySnapshot: Identifiable, Equatable {
    let category: HealthCategory
    let score: Int
    let severity: HealthSeverity
    let status: String
    let evidence: [HealthEvidence]
    let trend: HealthTrend
    let issues: [HealthIssue]
    var id: HealthCategory { category }
}

struct HealthHistoryPoint: Identifiable, Equatable {
    let date: Date
    let overallScore: Int
    let categoryScores: [HealthCategory: Int]
    let activeIssueCount: Int
    var id: Date { date }
}

struct MacHealthSnapshot: Equatable {
    let overallScore: Int
    let overallSeverity: HealthSeverity
    let overallTitle: String
    let summary: String
    let categories: [HealthCategorySnapshot]
    let activeIssues: [HealthIssue]
    let primaryRootCause: HealthRootCause?
    let secondaryFactors: [HealthEvidence]
    let recommendations: [HealthRecommendation]
    let timestamp: Date
    let baselineState: HealthBaselineState

    static let initial = MacHealthSnapshot(
        overallScore: 100,
        overallSeverity: .excellent,
        overallTitle: L10n.text("health.baseline.learning"),
        summary: L10n.text("health.summary.learning"),
        categories: HealthCategory.allCases.map {
            HealthCategorySnapshot(category: $0, score: 100, severity: .unavailable, status: L10n.text("Unavailable"), evidence: [], trend: .unavailable, issues: [])
        },
        activeIssues: [],
        primaryRootCause: nil,
        secondaryFactors: [],
        recommendations: [],
        timestamp: .distantPast,
        baselineState: .learning(samples: 0)
    )

    func category(_ category: HealthCategory) -> HealthCategorySnapshot {
        categories.first { $0.category == category }
            ?? HealthCategorySnapshot(category: category, score: 100, severity: .unavailable, status: L10n.text("Unavailable"), evidence: [], trend: .unavailable, issues: [])
    }
}

enum HealthThresholds {
    static let historyLimit = 900
    static let historySeconds: TimeInterval = 30 * 60
    static let baselineMinimumSamples = 30
    static let baselineMinimumDuration: TimeInterval = 120
    static let baselineAlpha = 0.02

    static let cpuElevated = 75.0
    static let cpuHigh = 90.0
    static let cpuCritical = 95.0
    static let computeMinimumDuration: TimeInterval = 20
    static let computeHighDuration: TimeInterval = 60
    static let computeCriticalDuration: TimeInterval = 180

    static let gpuElevated = 80.0
    static let gpuMinimumDuration: TimeInterval = 45
    static let aneMinimumDuration: TimeInterval = 60

    static let memoryMinimumDuration: TimeInterval = 15
    static let swapRapidGrowth = 512.0 * 1_024 * 1_024
    static let swapCriticalGrowth = 2.0 * 1_024 * 1_024 * 1_024

    static let temperatureElevated = 85.0
    static let temperatureHigh = 92.0
    static let temperatureCritical = 100.0
    static let thermalMinimumDuration: TimeInterval = 45
    static let thermalHighDuration: TimeInterval = 90
    static let batteryTemperatureElevated = 40.0
    static let batteryTemperatureHigh = 45.0

    static let powerAbsoluteHigh = 18.0
    static let powerBaselineMultiplier = 1.75
    static let powerMinimumDuration: TimeInterval = 60

    static let storageElevatedBytes = 20.0 * 1_000_000_000
    static let storageHighBytes = 10.0 * 1_000_000_000
    static let storageCriticalBytes = 5.0 * 1_000_000_000
    static let diskAbsoluteHigh = 300.0 * 1_000_000
    static let diskMinimumDuration: TimeInterval = 30

    static let recoveryDuration: TimeInterval = 30
}

private struct HealthBaselineMetric: Codable {
    var mean: Double
    var variance: Double
    var count: Int
    var firstDate: Date
    var lastDate: Date

    mutating func ingest(_ value: Double, date: Date) {
        guard value.isFinite else { return }
        let nextCount = min(count + 1, 10_000)
        let alpha = count < 50 ? 1.0 / Double(count + 1) : HealthThresholds.baselineAlpha
        let delta = value - mean
        mean += alpha * delta
        variance = max(0, (1 - alpha) * (variance + alpha * delta * delta))
        count = nextCount
        lastDate = date
    }

    var deviation: Double { sqrt(max(variance, 0)) }
    var isReady: Bool { count >= HealthThresholds.baselineMinimumSamples && lastDate.timeIntervalSince(firstDate) >= HealthThresholds.baselineMinimumDuration }
}

private struct HealthBaselineArchive: Codable {
    var metrics: [String: HealthBaselineMetric] = [:]
}

private struct HealthCondition {
    var startedAt: Date
    var lastTriggeredAt: Date
    var surfaced = false
}

private struct HealthRawPoint {
    let date: Date
    let values: [String: Double]
}

final class MacHealthEngine {
    private let defaults: UserDefaults?
    private let baselineKey = "macHealthBaseline.v1"
    private var baseline = HealthBaselineArchive()
    private var conditions: [String: HealthCondition] = [:]
    private var stableRootCauses: [String: HealthRootCause] = [:]
    private var rawHistory: [HealthRawPoint] = []
    private(set) var history: [HealthHistoryPoint] = []
    private var previousOverallScore: Double?
    private var previousCategoryScores: [HealthCategory: Double] = [:]
    private var lastBaselineSave = Date.distantPast

    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        if let data = defaults?.data(forKey: baselineKey), let archive = try? JSONDecoder().decode(HealthBaselineArchive.self, from: data) {
            baseline = archive
        }
    }

    func resetSession() {
        conditions.removeAll()
        stableRootCauses.removeAll()
        rawHistory.removeAll()
        history.removeAll()
        previousOverallScore = nil
        previousCategoryScores.removeAll()
    }

    func evaluate(_ snapshot: Snapshot, processes: [ProcessRecord] = []) -> MacHealthSnapshot {
        appendRaw(snapshot)
        var categories = [
            analyzeCompute(snapshot, processes: processes),
            analyzeMemory(snapshot, processes: processes),
            analyzeThermals(snapshot),
            analyzeBattery(snapshot, processes: processes),
            analyzeStorage(snapshot, processes: processes)
        ]
        categories = correlate(categories)
        let issues = categories.flatMap(\.issues).sorted(by: issueOrder)
        let rawOverall = overallScore(for: issues)
        let cappedOverall = applyCriticalCaps(rawOverall, issues: issues)
        let overall = smoothOverall(cappedOverall, hasCritical: issues.contains { $0.severity == .critical })
        let state = baselineState
        let primary = issues.compactMap(\.rootCause).first
        let secondary = secondaryFactors(from: issues, excluding: primary)
        let recommendations = uniqueRecommendations(issues.compactMap(\.recommendation))
        let severity = HealthSeverity.score(overall)
        let title = state.samples < HealthThresholds.baselineMinimumSamples && issues.isEmpty ? state.title : severity.title
        let summary = summary(for: issues, baselineState: state)
        let result = MacHealthSnapshot(
            overallScore: overall,
            overallSeverity: severity,
            overallTitle: title,
            summary: summary,
            categories: categories,
            activeIssues: issues,
            primaryRootCause: primary,
            secondaryFactors: secondary,
            recommendations: recommendations,
            timestamp: snapshot.date,
            baselineState: state
        )
        appendHistory(result)
        updateBaseline(snapshot, categories: categories)
        return result
    }

    private var baselineState: HealthBaselineState {
        let ready = baseline.metrics.values.filter(\.isReady)
        let samples = baseline.metrics.values.map(\.count).max() ?? 0
        return ready.count >= 4 ? .ready(samples: samples) : .learning(samples: samples)
    }

    private func analyzeCompute(_ snapshot: Snapshot, processes: [ProcessRecord]) -> HealthCategorySnapshot {
        var evidence: [HealthEvidence] = []
        var issues: [HealthIssue] = []
        if let cpu = finite(snapshot[.cpu]) {
            evidence.append(.init(id: "cpu", label: L10n.text("CPU"), value: Metric.cpu.format(cpu), detail: nil))
            let average = rollingAverage("cpu", seconds: 60) ?? cpu
            let dynamic = adaptiveThreshold("cpu", absolute: HealthThresholds.cpuElevated, deviations: 2.5)
            let triggered = average >= dynamic
            let root = processRoot(for: "compute.cpu", processes: processes, kind: .cpu, activelyTriggered: triggered)
            if let duration = observe("compute.cpu", triggered: triggered, recovered: average < dynamic - 10 && cpu < dynamic - 10, minimum: HealthThresholds.computeMinimumDuration, date: snapshot.date) {
                let severity: HealthSeverity
                let penalty: Int
                if average >= HealthThresholds.cpuCritical && duration >= HealthThresholds.computeCriticalDuration { severity = .critical; penalty = 46 }
                else if average >= HealthThresholds.cpuHigh && duration >= HealthThresholds.computeHighDuration { severity = .high; penalty = 30 }
                else { severity = .elevated; penalty = 15 }
                let durationText = formatDuration(duration)
                var issueEvidence = [
                    HealthEvidence(id: "cpu-average", label: L10n.text("health.evidence.averageCPU"), value: Metric.cpu.format(average), detail: nil),
                    HealthEvidence(id: "cpu-duration", label: L10n.text("health.evidence.duration"), value: durationText, detail: nil)
                ]
                if let peak = rollingPeak("cpu", seconds: 300) { issueEvidence.append(.init(id: "cpu-peak", label: L10n.text("health.evidence.peak"), value: Metric.cpu.format(peak), detail: nil)) }
                let recommendation = root.map {
                    HealthRecommendation(id: "compute.cpu", title: L10n.text("health.recommendation.reduceLoad"), detail: L10n.format("health.recommendation.closeProcess", $0.name))
                } ?? HealthRecommendation(id: "compute.cpu", title: L10n.text("health.recommendation.reduceLoad"), detail: L10n.text("health.recommendation.reduceCompute"))
                issues.append(.init(id: "compute.cpu", category: .compute, severity: severity, title: L10n.text("health.issue.highCPU"), summary: L10n.format("health.issue.cpuSustained", durationText), duration: duration, penalty: penalty, evidence: issueEvidence, rootCause: root, recommendation: recommendation))
            }
        }
        if let gpu = finite(snapshot[.gpu]) {
            evidence.append(.init(id: "gpu", label: L10n.text("GPU"), value: Metric.gpu.format(gpu), detail: nil))
            let average = rollingAverage("gpu", seconds: 60) ?? gpu
            if let duration = observe("compute.gpu", triggered: average >= HealthThresholds.gpuElevated, recovered: average < 65, minimum: HealthThresholds.gpuMinimumDuration, date: snapshot.date) {
                issues.append(.init(id: "compute.gpu", category: .compute, severity: average >= 95 ? .high : .elevated, title: L10n.text("health.issue.highGPU"), summary: L10n.format("health.issue.gpuSustained", formatDuration(duration)), duration: duration, penalty: average >= 95 ? 24 : 12, evidence: [.init(id: "gpu-average", label: L10n.text("health.evidence.averageGPU"), value: Metric.gpu.format(average), detail: nil)], rootCause: nil, recommendation: .init(id: "compute.gpu", title: L10n.text("health.recommendation.reduceLoad"), detail: L10n.text("health.recommendation.reduceGraphics"))))
            }
        }
        if let ane = finite(snapshot[.anePower]) {
            evidence.append(.init(id: "ane", label: L10n.text("ANE Power"), value: Metric.anePower.format(ane), detail: nil))
            if let baseline = baseline.metrics["anePower"], baseline.isReady {
                let threshold = max(0.75, baseline.mean + max(0.35, baseline.deviation * 3))
                if let duration = observe("compute.ane", triggered: ane >= threshold, recovered: ane < threshold * 0.7, minimum: HealthThresholds.aneMinimumDuration, date: snapshot.date) {
                    issues.append(.init(id: "compute.ane", category: .compute, severity: .elevated, title: L10n.text("health.issue.highANE"), summary: L10n.format("health.issue.aneSustained", formatDuration(duration)), duration: duration, penalty: 8, evidence: [.init(id: "ane-power", label: L10n.text("ANE Power"), value: Metric.anePower.format(ane), detail: L10n.text("health.evidence.baselineDeviation"))], rootCause: nil, recommendation: .init(id: "compute.ane", title: L10n.text("health.recommendation.reduceLoad"), detail: L10n.text("health.recommendation.reduceCompute"))))
                }
            }
        }
        let available = snapshot[.cpu] != nil || snapshot[.gpu] != nil || snapshot[.anePower] != nil
        return category(.compute, evidence: evidence, issues: issues, trend: trend("cpu", minimumDelta: 8), available: available)
    }

    private func analyzeMemory(_ snapshot: Snapshot, processes: [ProcessRecord]) -> HealthCategorySnapshot {
        var evidence: [HealthEvidence] = []
        var issues: [HealthIssue] = []
        let pressure = Int(snapshot.values["pressure"] ?? -1)
        if let used = finite(snapshot[.memory]) { evidence.append(.init(id: "memory-used", label: L10n.text("health.evidence.memoryUsed"), value: Metric.memory.format(used), detail: pressure == 1 ? L10n.text("health.evidence.ramNotPressure") : nil)) }
        if pressure >= 0 { evidence.append(.init(id: "memory-pressure", label: L10n.text("health.evidence.memoryPressure"), value: snapshot.pressureLabel, detail: nil)) }
        if let swap = finite(snapshot[.swap]) { evidence.append(.init(id: "swap", label: L10n.text("metric.swap"), value: Metric.swap.format(swap), detail: nil)) }
        if let compressed = finite(snapshot[.compressed]) { evidence.append(.init(id: "compressed", label: L10n.text("metric.compressed"), value: Metric.compressed.format(compressed), detail: nil)) }
        let growth = growth("swap", seconds: 15 * 60)
        let triggered = pressure == 4 || pressure == 2 || (growth ?? 0) >= HealthThresholds.swapRapidGrowth
        let root = processRoot(for: "memory.pressure", processes: processes, kind: .memory, totalMemory: snapshot[.memoryTotal], activelyTriggered: triggered)
        if let duration = observe("memory.pressure", triggered: triggered, recovered: pressure == 1 && (growth ?? 0) < HealthThresholds.swapRapidGrowth * 0.5, minimum: HealthThresholds.memoryMinimumDuration, date: snapshot.date) {
            let critical = pressure == 4 || (growth ?? 0) >= HealthThresholds.swapCriticalGrowth
            let severity: HealthSeverity = critical ? .critical : .high
            var issueEvidence = evidence.filter { ["memory-pressure", "swap", "compressed"].contains($0.id) }
            if let growth { issueEvidence.append(.init(id: "swap-growth", label: L10n.text("health.evidence.swapGrowth"), value: Metric.swap.format(growth), detail: L10n.text("health.evidence.last15Minutes"))) }
            let recommendation = root.map {
                HealthRecommendation(id: "memory.pressure", title: L10n.text("health.recommendation.reduceMemory"), detail: L10n.format("health.recommendation.closeMemoryProcess", $0.name))
            } ?? HealthRecommendation(id: "memory.pressure", title: L10n.text("health.recommendation.reduceMemory"), detail: L10n.text("health.recommendation.reduceMemoryGeneric"))
            issues.append(.init(id: "memory.pressure", category: .memory, severity: severity, title: L10n.text(critical ? "health.issue.criticalMemory" : "health.issue.memoryPressure"), summary: L10n.text(critical ? "health.issue.criticalMemorySummary" : "health.issue.memoryPressureSummary"), duration: duration, penalty: critical ? 58 : 34, evidence: issueEvidence, rootCause: root, recommendation: recommendation))
        }
        let available = snapshot[.memory] != nil || pressure >= 0
        return category(.memory, evidence: evidence, issues: issues, trend: trend("swap", minimumDelta: 256 * 1_024 * 1_024), available: available)
    }

    private func analyzeThermals(_ snapshot: Snapshot) -> HealthCategorySnapshot {
        var evidence: [HealthEvidence] = []
        var issues: [HealthIssue] = []
        let thermalState = Int(snapshot.values["thermalState"] ?? -1)
        if thermalState >= 0 { evidence.append(.init(id: "thermal-state", label: L10n.text("health.evidence.systemThermalState"), value: snapshot.thermalLabel, detail: L10n.text("health.evidence.appleThermalState"))) }
        let temperatures: [(String, String, Double?)] = [
            ("cpu-temperature", L10n.text("metric.cpuTemperature"), snapshot[.cpuTemperature]),
            ("gpu-temperature", L10n.text("metric.gpuTemperature"), snapshot[.gpuTemperature]),
            ("soc-temperature", L10n.text("health.evidence.socTemperature"), socTemperature(snapshot)),
            ("battery-temperature", L10n.text("metric.batteryTemperature"), snapshot[.batteryTemperature])
        ]
        for (id, label, value) in temperatures { if let value = finite(value) { evidence.append(.init(id: id, label: label, value: String(format: "%.1f°C", locale: Locale.current, value), detail: nil)) } }
        let siliconMaximum = [snapshot[.cpuTemperature], snapshot[.gpuTemperature], socTemperature(snapshot)].compactMap(finite).max()
        let hot = (siliconMaximum ?? 0) >= HealthThresholds.temperatureElevated
        let systemElevated = thermalState >= ProcessInfo.ThermalState.fair.rawValue
        let minimum: TimeInterval = thermalState >= ProcessInfo.ThermalState.serious.rawValue ? 0 : HealthThresholds.thermalMinimumDuration
        if let duration = observe("thermals.system", triggered: hot || systemElevated, recovered: thermalState <= ProcessInfo.ThermalState.nominal.rawValue && (siliconMaximum ?? 0) < 78, minimum: minimum, date: snapshot.date) {
            let severity: HealthSeverity
            let penalty: Int
            if thermalState >= ProcessInfo.ThermalState.critical.rawValue || (siliconMaximum ?? 0) >= HealthThresholds.temperatureCritical { severity = .critical; penalty = 66 }
            else if thermalState >= ProcessInfo.ThermalState.serious.rawValue || ((siliconMaximum ?? 0) >= HealthThresholds.temperatureHigh && duration >= HealthThresholds.thermalHighDuration) { severity = .high; penalty = 34 }
            else { severity = .elevated; penalty = 16 }
            issues.append(.init(id: "thermals.system", category: .thermals, severity: severity, title: L10n.text("health.issue.elevatedTemperature"), summary: L10n.format("health.issue.thermalSustained", formatDuration(duration)), duration: duration, penalty: penalty, evidence: evidence, rootCause: nil, recommendation: .init(id: "thermals.system", title: L10n.text("health.recommendation.coolMac"), detail: L10n.text("health.recommendation.reduceThermalLoad"))))
        }
        let available = thermalState >= 0 || !temperatures.compactMap { $0.2 }.isEmpty
        return category(.thermals, evidence: evidence, issues: issues, trend: trend("cpuTemperature", minimumDelta: 4), available: available)
    }

    private func analyzeBattery(_ snapshot: Snapshot, processes: [ProcessRecord]) -> HealthCategorySnapshot {
        var evidence: [HealthEvidence] = []
        var issues: [HealthIssue] = []
        if let health = finite(snapshot[.batteryHealth]) { evidence.append(.init(id: "battery-health", label: L10n.text("Battery Health"), value: Metric.batteryHealth.format(health), detail: L10n.text("health.evidence.hardwareSeparate"))) }
        if let power = finite(snapshot[.batteryPower]) { evidence.append(.init(id: "battery-power", label: L10n.text("Battery Power"), value: Metric.batteryPower.format(power), detail: nil)) }
        if let temperature = finite(snapshot[.batteryTemperature]) { evidence.append(.init(id: "battery-temperature", label: L10n.text("Battery Temperature"), value: Metric.batteryTemperature.format(temperature), detail: nil)) }
        let external = snapshot.values["externalPower"] == 1
        if let temperature = finite(snapshot[.batteryTemperature]), let duration = observe("battery.temperature", triggered: temperature >= HealthThresholds.batteryTemperatureElevated, recovered: temperature < 38, minimum: HealthThresholds.powerMinimumDuration, date: snapshot.date) {
            let severity: HealthSeverity = temperature >= HealthThresholds.batteryTemperatureHigh ? .high : .elevated
            issues.append(.init(id: "battery.temperature", category: .battery, severity: severity, title: L10n.text("health.issue.batteryHot"), summary: L10n.format("health.issue.batteryHotSummary", formatDuration(duration)), duration: duration, penalty: severity == .high ? 30 : 14, evidence: evidence.filter { $0.id == "battery-temperature" }, rootCause: nil, recommendation: .init(id: "battery.temperature", title: L10n.text("health.recommendation.coolBattery"), detail: L10n.text("health.recommendation.reduceThermalLoad"))))
        }
        if let power = finite(snapshot[.batteryPower]), power < 0, !external {
            let absolute = abs(power)
            let powerBaseline = baseline.metrics["batteryPower"]
            let relativeThreshold = powerBaseline?.isReady == true ? max(8, powerBaseline!.mean * HealthThresholds.powerBaselineMultiplier) : HealthThresholds.powerAbsoluteHigh
            let average = rollingAverageAbsolute("batteryPower", seconds: 60) ?? absolute
            let triggered = average >= relativeThreshold
            let root = processRoot(for: "battery.drain", processes: processes, kind: .energy, activelyTriggered: triggered)
            if let duration = observe("battery.drain", triggered: triggered, recovered: average < relativeThreshold * 0.7, minimum: HealthThresholds.powerMinimumDuration, date: snapshot.date) {
                let recommendation = root.map {
                    HealthRecommendation(id: "battery.drain", title: L10n.text("health.recommendation.reduceEnergy"), detail: L10n.format("health.recommendation.energyProcess", $0.name))
                } ?? HealthRecommendation(id: "battery.drain", title: L10n.text("health.recommendation.reduceEnergy"), detail: L10n.text("health.recommendation.reduceCompute"))
                issues.append(.init(id: "battery.drain", category: .battery, severity: average >= max(25, relativeThreshold * 1.5) ? .high : .elevated, title: L10n.text("health.issue.highDrain"), summary: L10n.format("health.issue.highDrainSummary", formatDuration(duration)), duration: duration, penalty: average >= max(25, relativeThreshold * 1.5) ? 30 : 16, evidence: [.init(id: "battery-drain-average", label: L10n.text("health.evidence.averageBatteryPower"), value: String(format: "−%.1f W", locale: Locale.current, average), detail: powerBaseline?.isReady == true ? L10n.text("health.evidence.aboveBaseline") : L10n.text("health.evidence.absoluteSafetyRule"))], rootCause: root, recommendation: recommendation))
            }
        } else {
            _ = observe("battery.drain", triggered: false, recovered: true, minimum: HealthThresholds.powerMinimumDuration, date: snapshot.date)
        }
        let available = snapshot[.battery] != nil || snapshot[.batteryPower] != nil || snapshot[.batteryTemperature] != nil
        return category(.battery, evidence: evidence, issues: issues, trend: trend("batteryPower", minimumDelta: 4), available: available)
    }

    private func analyzeStorage(_ snapshot: Snapshot, processes: [ProcessRecord]) -> HealthCategorySnapshot {
        var evidence: [HealthEvidence] = []
        var issues: [HealthIssue] = []
        let availableBytes = finite(snapshot[.storageAvailable])
        let totalBytes = finite(snapshot[.storageTotal])
        let freePercent: Double?
        if let availableBytes, let totalBytes { freePercent = availableBytes / max(totalBytes, 1) * 100 }
        else { freePercent = nil }
        if let availableBytes { evidence.append(.init(id: "storage-free", label: L10n.text("health.evidence.storageFree"), value: Metric.storageAvailable.format(availableBytes), detail: freePercent.map { String(format: "%.1f%%", locale: Locale.current, $0) })) }
        let isLow = availableBytes.map { $0 < HealthThresholds.storageElevatedBytes } == true || freePercent.map { $0 < 10 } == true
        if let duration = observe("storage.low", triggered: isLow, recovered: availableBytes.map { $0 >= HealthThresholds.storageElevatedBytes * 1.2 } == true && freePercent.map { $0 >= 12 } == true, minimum: 0, date: snapshot.date), let availableBytes {
            let severity: HealthSeverity
            let penalty: Int
            if availableBytes < HealthThresholds.storageCriticalBytes || (freePercent ?? 100) < 2 { severity = .critical; penalty = 52 }
            else if availableBytes < HealthThresholds.storageHighBytes || (freePercent ?? 100) < 5 { severity = .high; penalty = 36 }
            else { severity = .elevated; penalty = 20 }
            issues.append(.init(id: "storage.low", category: .storage, severity: severity, title: L10n.text("health.issue.lowStorage"), summary: L10n.format("health.issue.lowStorageSummary", Metric.storageAvailable.format(availableBytes)), duration: duration, penalty: penalty, evidence: evidence, rootCause: nil, recommendation: .init(id: "storage.low", title: L10n.text("health.recommendation.freeStorage"), detail: L10n.text("health.recommendation.freeStorageDetail"))))
        }
        let disk = (finite(snapshot[.diskRead]) ?? 0) + (finite(snapshot[.diskWrite]) ?? 0)
        if snapshot[.diskRead] != nil || snapshot[.diskWrite] != nil { evidence.append(.init(id: "disk-activity", label: L10n.text("health.evidence.diskActivity"), value: Metric.diskRead.format(disk), detail: nil)) }
        let diskBaseline = baseline.metrics["diskActivity"]
        let diskThreshold = diskBaseline?.isReady == true ? max(100_000_000, diskBaseline!.mean + max(100_000_000, diskBaseline!.deviation * 3)) : HealthThresholds.diskAbsoluteHigh
        let diskTriggered = disk >= diskThreshold
        let root = processRoot(for: "storage.activity", processes: processes, kind: .disk, activelyTriggered: diskTriggered)
        if let duration = observe("storage.activity", triggered: diskTriggered, recovered: disk < diskThreshold * 0.6, minimum: HealthThresholds.diskMinimumDuration, date: snapshot.date) {
            issues.append(.init(id: "storage.activity", category: .storage, severity: disk >= diskThreshold * 2 ? .high : .elevated, title: L10n.text("health.issue.heavyDisk"), summary: L10n.format("health.issue.diskSustained", formatDuration(duration)), duration: duration, penalty: disk >= diskThreshold * 2 ? 26 : 13, evidence: [.init(id: "disk-rate", label: L10n.text("health.evidence.diskActivity"), value: Metric.diskRead.format(disk), detail: diskBaseline?.isReady == true ? L10n.text("health.evidence.aboveBaseline") : L10n.text("health.evidence.absoluteSafetyRule"))], rootCause: root, recommendation: .init(id: "storage.activity", title: L10n.text("health.recommendation.reduceDisk"), detail: root.map { L10n.format("health.recommendation.diskProcess", $0.name) } ?? L10n.text("health.recommendation.reduceDiskGeneric"))))
        }
        let available = availableBytes != nil || snapshot[.diskRead] != nil || snapshot[.diskWrite] != nil
        return category(.storage, evidence: evidence, issues: issues, trend: trend("diskActivity", minimumDelta: 50_000_000), available: available)
    }

    private func category(_ category: HealthCategory, evidence: [HealthEvidence], issues: [HealthIssue], trend: HealthTrend, available: Bool) -> HealthCategorySnapshot {
        guard available else { return .init(category: category, score: 100, severity: .unavailable, status: L10n.text("Unavailable"), evidence: evidence, trend: .unavailable, issues: issues) }
        let rawScore = max(0, 100 - issues.reduce(0) { $0 + $1.penalty })
        let previous = previousCategoryScores[category]
        let alpha = previous.map { Double(rawScore) < $0 ? 0.65 : 0.25 } ?? 1
        let smoothed = previous.map { $0 + (Double(rawScore) - $0) * alpha } ?? Double(rawScore)
        previousCategoryScores[category] = smoothed
        let score = Int(smoothed.rounded())
        let severity = issues.map(\.severity).max() ?? HealthSeverity.score(score)
        let status = issues.sorted(by: issueOrder).first?.title ?? (category == .memory && evidence.contains { $0.id == "memory-used" && $0.detail != nil } ? L10n.text("health.status.memoryNormal") : severity.title)
        return .init(category: category, score: score, severity: severity, status: status, evidence: evidence, trend: trend, issues: issues)
    }

    private func correlate(_ categories: [HealthCategorySnapshot]) -> [HealthCategorySnapshot] {
        let allIssues = categories.flatMap(\.issues)
        let cpuIssue = allIssues.first { $0.id == "compute.cpu" }
        let thermalIssue = allIssues.first { $0.category == .thermals }
        let batteryIssue = allIssues.first { $0.id == "battery.drain" }
        guard let cpuIssue, thermalIssue != nil || batteryIssue != nil else { return categories }
        return categories.map { category in
            guard category.category == .compute else { return category }
            var revisedIssues = category.issues
            if let index = revisedIssues.firstIndex(where: { $0.id == cpuIssue.id }) {
                let issue = revisedIssues[index]
                var evidence = issue.evidence
                if thermalIssue != nil { evidence.append(.init(id: "correlation-temperature", label: L10n.text("health.evidence.correlation"), value: L10n.text("health.correlation.cpuThermal"), detail: nil)) }
                if batteryIssue != nil { evidence.append(.init(id: "correlation-energy", label: L10n.text("health.evidence.correlation"), value: L10n.text("health.correlation.cpuEnergy"), detail: nil)) }
                let correlatedSeverity = max(issue.severity, max(thermalIssue?.severity ?? .normal, batteryIssue?.severity ?? .normal))
                revisedIssues[index] = .init(id: issue.id, category: issue.category, severity: correlatedSeverity, title: L10n.text("health.issue.correlatedCompute"), summary: L10n.text("health.issue.correlatedComputeSummary"), duration: issue.duration, penalty: issue.penalty, evidence: evidence, rootCause: issue.rootCause, recommendation: issue.recommendation)
            }
            return .init(category: category.category, score: category.score, severity: revisedIssues.map(\.severity).max() ?? category.severity, status: revisedIssues.sorted(by: issueOrder).first?.title ?? category.status, evidence: category.evidence, trend: category.trend, issues: revisedIssues)
        }
    }

    private enum ProcessRootKind { case cpu, memory, energy, disk }

    private struct ProcessContribution {
        let process: ProcessRecord
        var value: Double
    }

    private func processRoot(for conditionID: String, processes: [ProcessRecord], kind: ProcessRootKind, totalMemory: Double? = nil, activelyTriggered: Bool) -> HealthRootCause? {
        if conditions[conditionID]?.surfaced == true { return stableRootCauses[conditionID] }
        guard activelyTriggered else { return stableRootCauses[conditionID] }
        if let root = processRoot(processes, kind: kind, totalMemory: totalMemory) {
            stableRootCauses[conditionID] = root
            return root
        }
        return stableRootCauses[conditionID]
    }

    private func processRoot(_ processes: [ProcessRecord], kind: ProcessRootKind, totalMemory: Double? = nil) -> HealthRootCause? {
        let contributions: [(ProcessRecord, Double)] = processes.compactMap { process in
            let value: Double?
            switch kind {
            case .cpu: value = process.cpuPercent
            case .memory: value = process.memoryBytes.map { Double($0) }
            case .energy: value = process.energyScore
            case .disk: value = process.diskTotalRate
            }
            guard let value, value.isFinite, value > 0 else { return nil }
            return (process, value)
        }
        var grouped: [String: ProcessContribution] = [:]
        for (process, value) in contributions {
            let key = process.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if var existing = grouped[key] {
                existing.value += value
                grouped[key] = existing
            } else {
                grouped[key] = .init(process: process, value: value)
            }
        }
        let scored = grouped.values.sorted { $0.value > $1.value }
        guard let first = scored.first else { return nil }
        switch kind {
        case .cpu where first.value < 5: return nil
        case .memory where first.value < 50 * 1_024 * 1_024: return nil
        case .energy where first.value < 1: return nil
        case .disk where first.value < 1_000_000: return nil
        default: break
        }
        let total = scored.reduce(0) { $0 + $1.value }
        let share = first.value / max(total, 1)
        let confidence: HealthConfidence
        switch kind {
        case .cpu:
            confidence = first.value >= 100 && share >= 0.45 ? .high : first.value >= 35 && share >= 0.25 ? .medium : .low
        case .memory:
            let systemShare = first.value / max(totalMemory ?? total, 1)
            confidence = systemShare >= 0.35 ? .high : systemShare >= 0.15 || share >= 0.4 ? .medium : .low
        case .energy, .disk:
            confidence = share >= 0.6 ? .high : share >= 0.35 ? .medium : .low
        }
        let label: String
        let value: String
        let role: String
        switch kind {
        case .cpu: label = L10n.text("CPU"); value = String(format: "%.0f%%", locale: Locale.current, first.value); role = L10n.text(confidence == .high ? "health.root.primaryCause" : "health.root.likelyContributor")
        case .memory: label = L10n.text("Memory"); value = ByteCountFormatter.string(fromByteCount: Int64(first.value), countStyle: .binary); role = L10n.text(confidence == .high ? "health.root.largestConsumer" : "health.root.likelyContributor")
        case .energy: label = L10n.text("Energy Score"); value = String(format: "%.0f", locale: Locale.current, first.value); role = L10n.text("health.root.likelyContributor")
        case .disk: label = L10n.text("Disk I/O"); value = Metric.diskRead.format(first.value); role = L10n.text(confidence == .high ? "health.root.primaryCause" : "health.root.likelyContributor")
        }
        return .init(processID: first.process.pid, name: first.process.name, confidence: confidence, role: role, evidence: [.init(id: "process-contribution", label: label, value: value, detail: L10n.format("health.evidence.processShare", Int((share * 100).rounded())))])
    }

    private func observe(_ id: String, triggered: Bool, recovered: Bool, minimum: TimeInterval, date: Date) -> TimeInterval? {
        if triggered {
            var state = conditions[id] ?? HealthCondition(startedAt: date, lastTriggeredAt: date)
            state.lastTriggeredAt = date
            if date.timeIntervalSince(state.startedAt) >= minimum { state.surfaced = true }
            conditions[id] = state
            return state.surfaced ? max(0, date.timeIntervalSince(state.startedAt)) : nil
        }
        guard let state = conditions[id] else { return nil }
        if !recovered {
            conditions[id] = state
            return state.surfaced ? max(0, state.lastTriggeredAt.timeIntervalSince(state.startedAt)) : nil
        }
        if !state.surfaced || date.timeIntervalSince(state.lastTriggeredAt) >= HealthThresholds.recoveryDuration {
            conditions[id] = nil
            stableRootCauses[id] = nil
            return nil
        }
        conditions[id] = state
        return max(0, state.lastTriggeredAt.timeIntervalSince(state.startedAt))
    }

    private func appendRaw(_ snapshot: Snapshot) {
        var values = snapshot.values
        values["diskActivity"] = (snapshot[.diskRead] ?? 0) + (snapshot[.diskWrite] ?? 0)
        if let batteryPower = snapshot[.batteryPower] { values["batteryPower"] = batteryPower }
        rawHistory.append(.init(date: snapshot.date, values: values))
        rawHistory.removeAll { $0.date < snapshot.date.addingTimeInterval(-HealthThresholds.historySeconds) }
        if rawHistory.count > HealthThresholds.historyLimit { rawHistory.removeFirst(rawHistory.count - HealthThresholds.historyLimit) }
    }

    private func appendHistory(_ snapshot: MacHealthSnapshot) {
        history.append(.init(date: snapshot.timestamp, overallScore: snapshot.overallScore, categoryScores: Dictionary(uniqueKeysWithValues: snapshot.categories.map { ($0.category, $0.score) }), activeIssueCount: snapshot.activeIssues.count))
        history.removeAll { $0.date < snapshot.timestamp.addingTimeInterval(-HealthThresholds.historySeconds) }
        if history.count > HealthThresholds.historyLimit { history.removeFirst(history.count - HealthThresholds.historyLimit) }
    }

    private func rollingValues(_ key: String, seconds: TimeInterval) -> [Double] {
        guard let date = rawHistory.last?.date else { return [] }
        return rawHistory.lazy.filter { $0.date >= date.addingTimeInterval(-seconds) }.compactMap { $0.values[key] }.filter(\.isFinite)
    }

    private func rollingAverage(_ key: String, seconds: TimeInterval) -> Double? {
        let values = rollingValues(key, seconds: seconds)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private func rollingAverageAbsolute(_ key: String, seconds: TimeInterval) -> Double? {
        let values = rollingValues(key, seconds: seconds).map(abs)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private func rollingPeak(_ key: String, seconds: TimeInterval) -> Double? { rollingValues(key, seconds: seconds).max() }

    private func growth(_ key: String, seconds: TimeInterval) -> Double? {
        guard let end = rawHistory.last, let endValue = end.values[key] else { return nil }
        let candidates = rawHistory.filter { $0.date >= end.date.addingTimeInterval(-seconds) }
        guard let startValue = candidates.first?.values[key], candidates.count > 1 else { return nil }
        return max(0, endValue - startValue)
    }

    private func trend(_ key: String, minimumDelta: Double) -> HealthTrend {
        let values = rollingValues(key, seconds: 60)
        guard values.count >= 2, let first = values.first, let last = values.last else { return .unavailable }
        let delta = last - first
        if delta >= minimumDelta { return .rising }
        if delta <= -minimumDelta { return .falling }
        return .stable
    }

    private func adaptiveThreshold(_ key: String, absolute: Double, deviations: Double) -> Double {
        guard let baseline = baseline.metrics[key], baseline.isReady else { return absolute }
        return max(absolute, baseline.mean + max(5, baseline.deviation * deviations))
    }

    private func updateBaseline(_ snapshot: Snapshot, categories: [HealthCategorySnapshot]) {
        let blocked = Set(categories.filter { !$0.issues.isEmpty }.map(\.category))
        let candidates: [(String, Double?, HealthCategory)] = [
            ("cpu", snapshot[.cpu], .compute),
            ("gpu", snapshot[.gpu], .compute),
            ("anePower", snapshot[.anePower], .compute),
            ("pressure", snapshot.values["pressure"], .memory),
            ("cpuTemperature", snapshot[.cpuTemperature], .thermals),
            ("gpuTemperature", snapshot[.gpuTemperature], .thermals),
            ("batteryPower", snapshot[.batteryPower].map(abs), .battery),
            ("diskActivity", snapshot[.diskRead] == nil && snapshot[.diskWrite] == nil ? nil : (snapshot[.diskRead] ?? 0) + (snapshot[.diskWrite] ?? 0), .storage)
        ]
        for (key, rawValue, category) in candidates {
            guard !blocked.contains(category), let value = finite(rawValue), baselineSafe(key, value: value, snapshot: snapshot) else { continue }
            if var metric = baseline.metrics[key] { metric.ingest(value, date: snapshot.date); baseline.metrics[key] = metric }
            else { baseline.metrics[key] = .init(mean: value, variance: 0, count: 1, firstDate: snapshot.date, lastDate: snapshot.date) }
        }
        guard snapshot.date.timeIntervalSince(lastBaselineSave) >= 60, let defaults, let data = try? JSONEncoder().encode(baseline) else { return }
        defaults.set(data, forKey: baselineKey)
        lastBaselineSave = snapshot.date
    }

    private func baselineSafe(_ key: String, value: Double, snapshot: Snapshot) -> Bool {
        switch key {
        case "cpu", "gpu": value < 70
        case "pressure": Int(value) == 1
        case "cpuTemperature", "gpuTemperature": value < 80 && Int(snapshot.values["thermalState"] ?? 0) == 0
        case "batteryPower": value < 15
        case "diskActivity": value < 200_000_000
        default: true
        }
    }

    private func overallScore(for issues: [HealthIssue]) -> Int {
        let weights = [1.0, 0.65, 0.4, 0.25, 0.15]
        let deduction = issues.enumerated().reduce(0.0) { partial, item in
            partial + Double(item.element.penalty) * (item.offset < weights.count ? weights[item.offset] : 0.1)
        }
        return max(0, min(100, Int((100 - deduction).rounded())))
    }

    private func applyCriticalCaps(_ score: Int, issues: [HealthIssue]) -> Int {
        var result = score
        for issue in issues where issue.severity == .critical {
            switch issue.category {
            case .thermals: result = min(result, 25)
            case .memory: result = min(result, 32)
            case .compute: result = min(result, 40)
            case .battery: result = min(result, 38)
            case .storage: result = min(result, 45)
            }
        }
        return result
    }

    private func smoothOverall(_ next: Int, hasCritical: Bool) -> Int {
        guard let previous = previousOverallScore else { previousOverallScore = Double(next); return next }
        let alpha = Double(next) < previous ? 0.55 : 0.18
        var result = previous + (Double(next) - previous) * alpha
        if hasCritical { result = min(result, Double(next)) }
        previousOverallScore = result
        return max(0, min(100, Int(result.rounded())))
    }

    private func summary(for issues: [HealthIssue], baselineState: HealthBaselineState) -> String {
        if let first = issues.first { return first.summary }
        if case .learning = baselineState { return L10n.text("health.summary.learning") }
        return L10n.text("health.summary.normal")
    }

    private func secondaryFactors(from issues: [HealthIssue], excluding root: HealthRootCause?) -> [HealthEvidence] {
        issues.dropFirst().prefix(3).map {
            HealthEvidence(id: "secondary-\($0.id)", label: $0.category.title, value: $0.title, detail: $0.evidence.first?.value)
        }
    }

    private func uniqueRecommendations(_ recommendations: [HealthRecommendation]) -> [HealthRecommendation] {
        var seen = Set<String>()
        return recommendations.filter { seen.insert($0.id).inserted }
    }

    private func issueOrder(_ lhs: HealthIssue, __ rhs: HealthIssue) -> Bool {
        if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
        return lhs.penalty > rhs.penalty
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded()))
        if seconds < 60 { return L10n.format("health.duration.seconds", seconds) }
        return L10n.format("health.duration.minutes", max(1, seconds / 60))
    }

    private func socTemperature(_ snapshot: Snapshot) -> Double? {
        let values = snapshot.sensors.compactMap { name, value -> Double? in
            let lower = name.lowercased()
            return lower.contains("soc") || lower.contains("system") ? finite(value) : nil
        }
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private func finite(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
    }
}
