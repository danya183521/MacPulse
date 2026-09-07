import AppKit
import Combine
import WidgetKit

// Единственная очередь опрашивает датчики; SwiftUI получает готовые снимки.
final class SensorWorker: @unchecked Sendable {
    private var native: MPNativeSensors?
    func reset() { native?.resetBaselines() }
    func sample() -> Snapshot {
        if native == nil { native = MPNativeSensors() }
        let raw = native!.sample()
        var snapshot = Snapshot()
        for (key, value) in raw {
            if let n = value as? NSNumber { snapshot.values[key] = n.doubleValue }
            if let s = value as? String { snapshot.info[key] = s }
        }
        snapshot.cores = (raw["cores"] as? [NSNumber])?.map(\.doubleValue) ?? []
        snapshot.sensors = raw["sensors"] as? [String: Double] ?? [:]
        snapshot.energyChannels = raw["energyChannels"] as? [String: Double] ?? [:]
        if let data = try? JSONSerialization.data(withJSONObject: raw["volumes"] ?? []), let volumes = try? JSONDecoder().decode([Volume].self, from: data) { snapshot.volumes = volumes }
        return snapshot
    }
}

@MainActor final class SamplingEngine: ObservableObject {
    @Published private(set) var snapshot = Snapshot()
    @Published private(set) var history = HistoryStore()
    @Published private(set) var widgetStatus = L10n.text("Waiting for first snapshot")
    @Published private(set) var samplingMilliseconds = 0.0
    @Published private(set) var paused = false
    let alerts = AlertEngine()
    private let worker = SensorWorker()
    private let widgetQueue = DispatchQueue(label: "local.macpulse.widget", qos: .utility)
    private let queue = DispatchQueue(label: "local.macpulse.sampling", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var subscriptions = Set<AnyCancellable>()
    private var observers: [NSObjectProtocol] = []
    private var lastWidgetWrite = Date.distantPast
    private var lastWidgetReload = Date.distantPast
    private let preferences: Preferences
    init(preferences: Preferences) {
        self.preferences = preferences
        preferences.$interval.removeDuplicates().sink { [weak self] rate in self?.start(rate) }.store(in: &subscriptions)
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.stopForSleep() } })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in guard let self else { return }; self.paused = false; self.start(self.preferences.interval) } })
    }
    func shutdown() {
        timer?.cancel(); timer = nil
        subscriptions.removeAll()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
    }
    private func stopForSleep() { paused = true; timer?.cancel(); timer = nil; queue.async { [worker] in worker.reset() } }
    private func start(_ interval: Double) {
        timer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self, worker] in
            let start = ProcessInfo.processInfo.systemUptime
            let snapshot = autoreleasepool { worker.sample() }
            let elapsed = (ProcessInfo.processInfo.systemUptime-start)*1000
            Task { @MainActor [weak self] in self?.receive(snapshot, duration: elapsed) }
        }
        self.timer = timer
        timer.resume()
    }
    private func receive(_ value: Snapshot, duration: Double) {
        snapshot = value
        samplingMilliseconds = duration
        history.append(value)
        alerts.evaluate(value, preferences: preferences)
        if value.date.timeIntervalSince(lastWidgetWrite) >= 60 {
            let widget = WidgetSnapshot(date: value.date, cpu: value[.cpu], memory: value[.memory], battery: value[.battery], temperature: value[.cpuTemperature])
            lastWidgetWrite = value.date
            if WidgetSnapshot.isConfigured {
                widgetQueue.async { [weak self] in
                    let message: String
                    do { try widget.write(); message = L10n.text("Shared snapshot updated") }
                    catch { message = L10n.format("Shared container: %@", error.localizedDescription) }
                    Task { @MainActor [weak self] in self?.widgetStatus = message }
                }
            } else { widgetStatus = L10n.text("Developer signing required for shared widget data") }
        }
        if WidgetSnapshot.isConfigured && value.date.timeIntervalSince(lastWidgetReload) >= 900 {
            WidgetCenter.shared.reloadTimelines(ofKind: "MacPulseWidget")
            lastWidgetReload = value.date
        }
    }
    var menuText: String {
        let items = preferences.menu
        var result: [String] = []
        for metric in items {
            let text = [metric.menuPrefix, metric.format(snapshot[metric], compact: true)].filter { !$0.isEmpty }.joined(separator: " ")
            let candidate = (result + [text]).joined(separator: "  ")
            let width = (candidate as NSString).size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)]).width
            if width > 310 { break }
            result.append(text)
        }
        if result.count < items.count { result.append("+\(items.count-result.count)") }
        return result.joined(separator: "  ")
    }
}
