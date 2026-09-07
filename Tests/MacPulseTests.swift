import XCTest
@testable import MacPulse

final class MacPulseTests: XCTestCase {
    func testUnavailableNeverFormatsAsZero() {
        for metric in Metric.allCases { XCTAssertEqual(metric.format(nil), "—"); XCTAssertEqual(metric.format(.nan), "—") }
        XCTAssertEqual(Metric.download.format(1_200_000, compact: true), String(format: "%.1fM", locale: Locale.current, 1.2))
        XCTAssertEqual(Metric.cpu.format(0), "0%")
    }
    func testAlertCooldownSurvivesPolicyRestore() {
        let now = Date()
        var policy = AlertPolicy(lastSent: ["temperature": now])
        _ = policy.evaluate(Snapshot(date: now, values: ["cpuTemperature": 95]), temperature: 90, battery: 15, storage: 10)
        XCTAssertTrue(policy.evaluate(Snapshot(date: now.addingTimeInterval(31), values: ["cpuTemperature": 95]), temperature: 90, battery: 15, storage: 10).isEmpty)
        XCTAssertEqual(policy.evaluate(Snapshot(date: now.addingTimeInterval(3601), values: ["cpuTemperature": 95]), temperature: 90, battery: 15, storage: 10).count, 1)
    }
    func testHistoryBoundAndExpiry() {
        var history = HistoryStore(limit: 10)
        let start = Date()
        for i in 0..<30 { history.append(Snapshot(date: start.addingTimeInterval(Double(i)), values: ["cpu": Double(i)])) }
        XCTAssertEqual(history.points.count, 10)
        XCTAssertEqual(history.points.first?.values["cpu"], 20)
        history.append(Snapshot(date: start.addingTimeInterval(3600)))
        XCTAssertEqual(history.points.count, 1)
    }
    @MainActor func testPreferencesPersistOrderAndEmptySelection() {
        let suite = "local.macpulse.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = Preferences(defaults: defaults)
        first.menu = [.cpu,.battery,.memory]; first.move(.memory, by: -1); first.interval = 5; first.appearance = "Dark"
        let restored = Preferences(defaults: defaults)
        XCTAssertEqual(restored.menu, [.cpu,.memory,.battery]); XCTAssertEqual(restored.interval, 5); XCTAssertEqual(restored.appearance, "Dark")
        restored.menu = []
        XCTAssertTrue(Preferences(defaults: defaults).menu.isEmpty)
    }
    func testAlertsRequireSustainedConditionAndCooldown() {
        var policy = AlertPolicy()
        let start = Date()
        func snapshot(_ seconds: Double, _ cpu: Double = 95) -> Snapshot { Snapshot(date: start.addingTimeInterval(seconds), values: ["cpuTemperature": cpu]) }
        XCTAssertTrue(policy.evaluate(snapshot(0), temperature: 90, battery: 15, storage: 10).isEmpty)
        XCTAssertTrue(policy.evaluate(snapshot(29), temperature: 90, battery: 15, storage: 10).isEmpty)
        XCTAssertEqual(policy.evaluate(snapshot(30), temperature: 90, battery: 15, storage: 10).count, 1)
        XCTAssertTrue(policy.evaluate(snapshot(60), temperature: 90, battery: 15, storage: 10).isEmpty)
        XCTAssertTrue(policy.evaluate(snapshot(100, 70), temperature: 90, battery: 15, storage: 10).isEmpty)
        XCTAssertTrue(policy.evaluate(snapshot(3700), temperature: 90, battery: 15, storage: 10).isEmpty)
        XCTAssertEqual(policy.evaluate(snapshot(3731), temperature: 90, battery: 15, storage: 10).count, 1)
    }
    func testNetworkTransitionsResetAnd64BitCounters() {
        let counters = MPNetworkCounters()
        XCTAssertTrue(counters.updateInterface("en0", received: 100, sent: 200, timestamp: 1).isEmpty)
        let rates = counters.updateInterface("en0", received: 300, sent: 600, timestamp: 3)
        XCTAssertEqual(rates["download"], 100); XCTAssertEqual(rates["upload"], 200)
        XCTAssertTrue(counters.updateInterface("en1", received: 900, sent: 900, timestamp: 4).isEmpty)
        XCTAssertTrue(counters.updateInterface(nil, received: nil, sent: nil, timestamp: 5).isEmpty)
        XCTAssertTrue(counters.updateInterface("en1", received: 1000, sent: 1000, timestamp: 6).isEmpty)
        XCTAssertTrue(counters.updateInterface("en1", received: 10, sent: 10, timestamp: 7).isEmpty)
        XCTAssertTrue(counters.updateInterface("en1", received: 100, sent: 100, timestamp: 100).isEmpty)
        counters.reset()
        _ = counters.updateInterface("en0", received: NSNumber(value: UInt64(UInt32.max)-9), sent: 100, timestamp: 200)
        let wrapped = counters.updateInterface("en0", received: NSNumber(value: UInt64(UInt32.max)+11), sent: 200, timestamp: 201)
        XCTAssertEqual(wrapped["download"], 20); XCTAssertEqual(wrapped["upload"], 100)
    }
    @MainActor func testNativeStatusItemReceivesLiveSamples() async throws {
        let suite = "local.macpulse.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let preferences = Preferences(defaults: defaults)
        preferences.menu = [.cpu]; preferences.interval = 1
        let engine = SamplingEngine(preferences: preferences)
        let status = StatusBarController(engine: engine, preferences: preferences)
        defer { status.shutdown(); engine.shutdown(); defaults.removePersistentDomain(forName: suite) }
        try await Task.sleep(for: .seconds(2.5))
        XCTAssertNotNil(engine.snapshot[.cpu])
        XCTAssertTrue(status.item.isVisible)
        let button = try XCTUnwrap(status.item.button)
        XCTAssertTrue(button.title.contains("CPU")); XCTAssertFalse(button.title.contains("—"))
        XCTAssertGreaterThan(button.window?.frame.width ?? 0, 20)
        preferences.menu = [.memory]
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(button.title.contains("RAM"))
        XCTAssertEqual(button.title.trimmingCharacters(in: .whitespaces), engine.menuText)
    }
    func testWidgetPayloadRoundTripUsesRealSample() throws {
        let source = SensorWorker().sample()
        let payload = WidgetSnapshot(date: source.date, cpu: source[.cpu], memory: source[.memory], battery: source[.battery], temperature: source[.cpuTemperature])
        let restored = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(payload))
        XCTAssertEqual(restored.memory, source[.memory])
        XCTAssertEqual(restored.battery, source[.battery])
        XCTAssertEqual(restored.temperature, source[.cpuTemperature])
        XCTAssertNil(restored.cpu)
    }
    func testActualSamplingAndReset() throws {
        let worker = SensorWorker()
        let first = worker.sample()
        XCTAssertNil(first[.cpu])
        XCTAssertEqual(first[.memoryTotal], Double(ProcessInfo.processInfo.physicalMemory))
        Thread.sleep(forTimeInterval: 1)
        let second = worker.sample()
        let cpu = try XCTUnwrap(second[.cpu]); XCTAssertTrue((0...100).contains(cpu)); XCTAssertEqual(second.cores.count, ProcessInfo.processInfo.processorCount)
        XCTAssertGreaterThan(try XCTUnwrap(second[.memoryUsed]), 0)
        XCTAssertEqual(try XCTUnwrap(second[.memoryAvailable]) + second[.memoryUsed]!, second[.memoryTotal]!, accuracy: 1)
        if first.info["interface"] == second.info["interface"], second.info["interface"] != "Offline" {
            XCTAssertNotNil(second[.download]); XCTAssertNotNil(second[.upload])
        }
        for value in second.sensors.values { XCTAssertTrue((0...150).contains(value)) }
        worker.reset(); let reset = worker.sample(); XCTAssertNil(reset[.cpu]); XCTAssertNil(reset[.download])
    }

    func testProcessSamplerEnumeratesCurrentProcessAndKeepsNetworkUnavailable() throws {
        let sampler = ProcessSampler()
        let first = sampler.sample()
        XCTAssertTrue(first.records.contains { $0.pid == getpid() })
        XCTAssertFalse(first.records.isEmpty)
        Thread.sleep(forTimeInterval: 1.1)
        let second = sampler.sample()
        let current = try XCTUnwrap(second.records.first { $0.pid == getpid() })
        XCTAssertGreaterThan(current.memoryBytes ?? 0, 0)
        XCTAssertNotNil(current.cpuPercent)
        XCTAssertNil(current.networkDownload)
        XCTAssertNil(current.networkUpload)
        XCTAssertGreaterThanOrEqual(current.diskReadRate ?? 0, 0)
        XCTAssertGreaterThanOrEqual(current.diskWriteRate ?? 0, 0)
    }

    func testProcessPresentationMetadata() {
        XCTAssertEqual(ProcessScope.all.titleKey, "All Processes")
        XCTAssertEqual(ProcessScope.user.titleKey, "User Processes")
        XCTAssertEqual(ProcessSort.energy.titleKey, "Energy Score")
        XCTAssertEqual(ProcessSort.disk.titleKey, "Disk I/O")
    }

    func testBatteryCapacityHealthAndUnitConversions() {
        XCTAssertEqual(BatteryMath.capacityHealth(fullCharge: 3418, design: 4382)!, 78.0009, accuracy: 0.01)
        XCTAssertNil(BatteryMath.capacityHealth(fullCharge: 0, design: 4382))
        XCTAssertEqual(BatteryMath.watts(voltage: 12.39, current: 1.932)!, 23.935, accuracy: 0.01)
        XCTAssertEqual(BatteryMath.watts(voltage: 12.39, current: -1.932)!, -23.935, accuracy: 0.01)
        XCTAssertNil(BatteryMath.watts(voltage: 0, current: 1))
    }

    func testBatteryRatesSmoothingAndETA() {
        XCTAssertEqual(BatteryMath.percentRatePerHour(oldLevel: 60, newLevel: 61, elapsed: 60)!, 60, accuracy: 0.001)
        XCTAssertEqual(BatteryMath.percentRatePerHour(oldLevel: 61, newLevel: 60, elapsed: 60)!, -60, accuracy: 0.001)
        XCTAssertNil(BatteryMath.percentRatePerHour(oldLevel: 60, newLevel: 61, elapsed: 2))
        XCTAssertEqual(BatteryMath.smooth(previous: 10, next: 20, alpha: 0.2), 12, accuracy: 0.001)
        XCTAssertEqual(BatteryMath.remainingHours(availableCapacityMilliampHours: 2000, voltage: 12, powerWatts: -6)!, 4, accuracy: 0.001)
        XCTAssertEqual(BatteryMath.timeToFullHours(level: 60, chargeRatePercentPerHour: 30)!, 1.3333, accuracy: 0.001)
        XCTAssertNil(BatteryMath.timeToFullHours(level: 60, chargeRatePercentPerHour: nil))
    }

    func testBatteryBaselineAndInvalidSamples() {
        XCTAssertFalse(BatteryMath.highEnergy(powerWatts: -12, baselineWatts: 8, sustainedSamples: 2))
        XCTAssertTrue(BatteryMath.highEnergy(powerWatts: -16, baselineWatts: 8, sustainedSamples: 3))
        XCTAssertFalse(BatteryMath.highEnergy(powerWatts: .nan, baselineWatts: 8, sustainedSamples: 3))
        XCTAssertNil(BatteryMath.average([]))
        XCTAssertEqual(BatteryMath.average([2, 4, 6])!, 4, accuracy: 0.001)
    }

    @MainActor func testBatteryHistoryIsBoundedAndStateIsDerived() {
        let intelligence = BatteryIntelligence(historyLimit: 4)
        let start = Date()
        for i in 0..<8 {
            intelligence.ingest(Snapshot(date: start.addingTimeInterval(Double(i * 30)), values: [
                "battery": 70 - Double(i), "currentCapacity": 2500, "maxCapacity": 3400,
                "designCapacity": 4400, "voltage": 12, "amperage": -1, "batteryPower": -12,
                "externalPower": 0, "charging": 0, "batteryTemperature": 30
            ]))
        }
        XCTAssertEqual(intelligence.history.count, 4)
        XCTAssertEqual(intelligence.state, .discharging)
        XCTAssertEqual(intelligence.health!, 77.2727, accuracy: 0.01)
        XCTAssertEqual(intelligence.estimatedRemainingHours!, 2.5, accuracy: 0.001)
    }
}
