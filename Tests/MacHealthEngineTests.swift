import XCTest
@testable import MacPulse

final class MacHealthEngineTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testHealthyIdleMacHasHighScoreAndNoIssues() {
        let engine = MacHealthEngine(defaults: nil)
        let result = engine.evaluate(snapshot(0))
        XCTAssertGreaterThanOrEqual(result.overallScore, 90)
        XCTAssertTrue(result.activeIssues.isEmpty)
    }

    func testTwoSecondCPUSpikeIsSuppressed() {
        let engine = MacHealthEngine(defaults: nil)
        XCTAssertTrue(engine.evaluate(snapshot(0, cpu: 99)).activeIssues.isEmpty)
        XCTAssertTrue(engine.evaluate(snapshot(2, cpu: 99)).activeIssues.isEmpty)
        XCTAssertTrue(engine.evaluate(snapshot(4, cpu: 8)).activeIssues.isEmpty)
    }

    func testSustainedCPULoadFindsDominantProcess() {
        let engine = MacHealthEngine(defaults: nil)
        let processes = [process(name: "Codex", cpu: 164, memory: 1_000_000_000), process(name: "Safari", cpu: 12, memory: 500_000_000)]
        var result = MacHealthSnapshot.initial
        for second in stride(from: 0.0, through: 90, by: 15) { result = engine.evaluate(snapshot(second, cpu: 96), processes: processes) }
        let issue = result.activeIssues.first { $0.id == "compute.cpu" }
        XCTAssertNotNil(issue)
        XCTAssertEqual(issue?.rootCause?.name, "Codex")
        XCTAssertEqual(issue?.rootCause?.confidence, .high)
        XCTAssertLessThan(result.category(.compute).score, 90)
    }

    func testSustainedCPULoadGroupsSameNamedWorkers() {
        let engine = MacHealthEngine(defaults: nil)
        let processes = [
            process(name: "RenderWorker", cpu: 72, memory: 300_000_000, bundleIdentifier: "local.worker.one"),
            process(name: "RenderWorker", cpu: 69, memory: 300_000_000, bundleIdentifier: "local.worker.two"),
            process(name: "Safari", cpu: 50, memory: 500_000_000)
        ]
        var result = MacHealthSnapshot.initial
        for second in stride(from: 0.0, through: 90, by: 15) { result = engine.evaluate(snapshot(second, cpu: 96), processes: processes) }
        XCTAssertEqual(result.activeIssues.first { $0.id == "compute.cpu" }?.rootCause?.name, "RenderWorker")
        XCTAssertEqual(result.activeIssues.first { $0.id == "compute.cpu" }?.rootCause?.confidence, .high)
    }

    func testHighRAMWithNormalPressureRemainsNormal() {
        let engine = MacHealthEngine(defaults: nil)
        let result = engine.evaluate(snapshot(0, memory: 95, pressure: 1, swap: 120_000_000))
        XCTAssertTrue(result.category(.memory).issues.isEmpty)
        XCTAssertGreaterThanOrEqual(result.category(.memory).score, 90)
    }

    func testCriticalPressureAndRapidSwapGrowthIsCritical() {
        let engine = MacHealthEngine(defaults: nil)
        _ = engine.evaluate(snapshot(0, memory: 94, pressure: 4, swap: 1_000_000_000))
        let result = engine.evaluate(snapshot(20, memory: 95, pressure: 4, swap: 4_000_000_000), processes: [process(name: "Chrome", cpu: 5, memory: 6_400_000_000)])
        XCTAssertEqual(result.category(.memory).severity, .critical)
        XCTAssertEqual(result.category(.memory).issues.first?.rootCause?.name, "Chrome")
    }

    func testShortTemperatureSpikeDoesNotCreateIssue() {
        let engine = MacHealthEngine(defaults: nil)
        XCTAssertTrue(engine.evaluate(snapshot(0, cpuTemperature: 96)).category(.thermals).issues.isEmpty)
        XCTAssertTrue(engine.evaluate(snapshot(2, cpuTemperature: 55)).category(.thermals).issues.isEmpty)
    }

    func testSustainedHighTemperatureCreatesThermalIssue() {
        let engine = MacHealthEngine(defaults: nil)
        _ = engine.evaluate(snapshot(0, cpuTemperature: 94))
        _ = engine.evaluate(snapshot(50, cpuTemperature: 94))
        let result = engine.evaluate(snapshot(70, cpuTemperature: 94))
        XCTAssertFalse(result.category(.thermals).issues.isEmpty)
        XCTAssertLessThan(result.category(.thermals).score, 90)
    }

    func testTwoSecondBatteryDrainSpikeIsSuppressed() {
        let engine = MacHealthEngine(defaults: nil)
        XCTAssertTrue(engine.evaluate(snapshot(0, batteryPower: -24)).category(.battery).issues.isEmpty)
        XCTAssertTrue(engine.evaluate(snapshot(2, batteryPower: -24)).category(.battery).issues.isEmpty)
        XCTAssertTrue(engine.evaluate(snapshot(4, batteryPower: -6)).category(.battery).issues.isEmpty)
    }

    func testSustainedBatteryDrainRelativeToBaselineDegradesBattery() {
        let engine = MacHealthEngine(defaults: nil)
        for index in 0..<31 { _ = engine.evaluate(snapshot(Double(index * 5), batteryPower: -6)) }
        var result = MacHealthSnapshot.initial
        for second in stride(from: 160.0, through: 280, by: 15) { result = engine.evaluate(snapshot(second, cpu: 82, batteryPower: -16)) }
        XCTAssertNotNil(result.activeIssues.first { $0.id == "battery.drain" })
        XCTAssertLessThan(result.category(.battery).score, 90)
    }

    func testLowDiskSpaceDegradesStorageImmediately() {
        let engine = MacHealthEngine(defaults: nil)
        let result = engine.evaluate(snapshot(0, storageAvailable: 8_000_000_000, storageTotal: 500_000_000_000))
        XCTAssertNotNil(result.activeIssues.first { $0.id == "storage.low" })
        XCTAssertGreaterThanOrEqual(result.category(.storage).severity, .high)
    }

    func testMultipleIssuesCreateCorrelatedDiagnosis() {
        let engine = MacHealthEngine(defaults: nil)
        let processes = [process(name: "Codex", cpu: 170, memory: 1_500_000_000, energy: 92), process(name: "Other", cpu: 20, memory: 500_000_000, energy: 8)]
        var result = MacHealthSnapshot.initial
        for second in stride(from: 0.0, through: 90, by: 15) {
            result = engine.evaluate(snapshot(second, cpu: 97, cpuTemperature: 95, thermalState: 2, batteryPower: -24), processes: processes)
        }
        XCTAssertEqual(result.primaryRootCause?.name, "Codex")
        XCTAssertEqual(result.activeIssues.first { $0.category == .compute }?.title, L10n.text("health.issue.correlatedCompute"))
        XCTAssertGreaterThanOrEqual(result.activeIssues.count, 3)
    }

    func testRecoveryClearsIssueAndScoreRisesSmoothly() {
        let engine = MacHealthEngine(defaults: nil)
        var loaded = MacHealthSnapshot.initial
        for second in stride(from: 0.0, through: 90, by: 15) { loaded = engine.evaluate(snapshot(second, cpu: 97)) }
        var recovered = loaded
        for second in stride(from: 105.0, through: 240, by: 15) { recovered = engine.evaluate(snapshot(second, cpu: 8)) }
        XCTAssertNil(recovered.activeIssues.first { $0.id == "compute.cpu" })
        XCTAssertGreaterThan(recovered.overallScore, loaded.overallScore)
        XCTAssertLessThanOrEqual(recovered.overallScore, 100)
    }

    func testRecoveryKeepsTheObservedRootCauseUntilIssueClears() {
        let engine = MacHealthEngine(defaults: nil)
        let load = [process(name: "RenderWorker", cpu: 180, memory: 400_000_000)]
        for second in stride(from: 0.0, through: 90, by: 15) { _ = engine.evaluate(snapshot(second, cpu: 97), processes: load) }
        _ = engine.evaluate(snapshot(105, cpu: 8))
        let recovering = engine.evaluate(snapshot(120, cpu: 8))
        XCTAssertEqual(recovering.activeIssues.first { $0.id == "compute.cpu" }?.rootCause?.name, "RenderWorker")
    }

    func testInsufficientBaselineShowsLearning() {
        let engine = MacHealthEngine(defaults: nil)
        var result = MacHealthSnapshot.initial
        for index in 0..<5 { result = engine.evaluate(snapshot(Double(index * 5))) }
        if case .learning(let samples) = result.baselineState { XCTAssertLessThan(samples, HealthThresholds.baselineMinimumSamples) }
        else { XCTFail("Baseline must still be learning") }
    }

    func testMissingSensorsAreHandledWithoutIssue() {
        let engine = MacHealthEngine(defaults: nil)
        let result = engine.evaluate(Snapshot(date: start))
        XCTAssertTrue(result.activeIssues.isEmpty)
        XCTAssertEqual(result.category(.thermals).severity, .unavailable)
    }

    func testHealthHistoryIsBounded() {
        let engine = MacHealthEngine(defaults: nil)
        for index in 0..<1_000 { _ = engine.evaluate(snapshot(Double(index * 2))) }
        XCTAssertLessThanOrEqual(engine.history.count, HealthThresholds.historyLimit)
        XCTAssertLessThanOrEqual(engine.history.last!.date.timeIntervalSince(engine.history.first!.date), HealthThresholds.historySeconds)
    }

    func testSignificantHealthAlertUsesCooldownAndRecoveryDebounce() {
        var policy = HealthAlertPolicy()
        let issue = HealthIssue(id: "compute.cpu", category: .compute, severity: .high, title: "High CPU", summary: "CPU is high.", duration: 60, penalty: 30, evidence: [], rootCause: nil, recommendation: nil)
        let active = health(at: 0, issues: [issue])
        XCTAssertEqual(policy.evaluate(active).count, 1)
        XCTAssertTrue(policy.evaluate(health(at: 10, issues: [issue])).isEmpty)
        XCTAssertTrue(policy.evaluate(health(at: 20, issues: [])).isEmpty)
        XCTAssertEqual(policy.evaluate(health(at: 51, issues: [])).first?.id, "health.recovered.compute.cpu")
    }

    private func snapshot(
        _ seconds: Double,
        cpu: Double = 8,
        memory: Double = 55,
        pressure: Double = 1,
        swap: Double = 100_000_000,
        cpuTemperature: Double = 52,
        thermalState: Double = 0,
        batteryPower: Double = -6,
        storageAvailable: Double = 250_000_000_000,
        storageTotal: Double = 500_000_000_000
    ) -> Snapshot {
        Snapshot(date: start.addingTimeInterval(seconds), values: [
            "cpu": cpu,
            "gpu": 5,
            "memory": memory,
            "memoryTotal": 16_000_000_000,
            "pressure": pressure,
            "swap": swap,
            "compressed": 500_000_000,
            "cpuTemperature": cpuTemperature,
            "gpuTemperature": 45,
            "thermalState": thermalState,
            "battery": 70,
            "batteryHealth": 85,
            "batteryTemperature": 31,
            "batteryPower": batteryPower,
            "externalPower": 0,
            "storageAvailable": storageAvailable,
            "storageTotal": storageTotal,
            "diskRead": 2_000_000,
            "diskWrite": 1_000_000
        ])
    }

    private func process(name: String, cpu: Double, memory: UInt64, energy: Double = 20, disk: Double = 0, bundleIdentifier: String? = nil) -> ProcessRecord {
        ProcessRecord(pid: Int32(abs((name + (bundleIdentifier ?? "")).hashValue % 30_000) + 100), name: name, executablePath: nil, bundleIdentifier: bundleIdentifier, isApplication: true, isUserProcess: true, parentPID: 1, startDate: start, cpuPercent: cpu, memoryBytes: memory, energyScore: energy, networkDownload: nil, networkUpload: nil, diskReadRate: disk, diskWriteRate: 0, diskReadBytes: nil, diskWriteBytes: nil, threadCount: 4, processState: "running")
    }

    private func health(at seconds: Double, issues: [HealthIssue]) -> MacHealthSnapshot {
        MacHealthSnapshot(overallScore: issues.isEmpty ? 95 : 50, overallSeverity: issues.isEmpty ? .excellent : .high, overallTitle: "", summary: "", categories: [], activeIssues: issues, primaryRootCause: nil, secondaryFactors: [], recommendations: [], timestamp: start.addingTimeInterval(seconds), baselineState: .ready(samples: 100))
    }
}
