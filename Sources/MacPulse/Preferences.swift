import SwiftUI
import ServiceManagement

@MainActor final class Preferences: ObservableObject {
    private let defaults: UserDefaults
    @Published var menu: [Metric] { didSet { defaults.set(menu.map(\.rawValue), forKey: "menu") } }
    @Published var interval: Double { didSet { defaults.set(interval, forKey: "interval") } }
    @Published var appearance: String { didSet { defaults.set(appearance, forKey: "appearance") } }
    @Published var alertsEnabled: Bool { didSet { defaults.set(alertsEnabled, forKey: "alertsEnabled") } }
    @Published var temperatureThreshold: Double { didSet { defaults.set(temperatureThreshold, forKey: "temperatureThreshold") } }
    @Published var batteryThreshold: Double { didSet { defaults.set(batteryThreshold, forKey: "batteryThreshold") } }
    @Published var storageThreshold: Double { didSet { defaults.set(storageThreshold, forKey: "storageThreshold") } }
    @Published var processInterval: Double { didSet { defaults.set(processInterval, forKey: "processInterval") } }
    @Published var processTopLimit: Int { didSet { defaults.set(processTopLimit, forKey: "processTopLimit") } }
    @Published var showSystemProcesses: Bool { didSet { defaults.set(showSystemProcesses, forKey: "showSystemProcesses") } }
    @Published var loginMessage = ""
    var colorScheme: ColorScheme? { appearance == "Dark" ? .dark : appearance == "Light" ? .light : nil }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.stringArray(forKey: "menu")?.compactMap(Metric.init(rawValue:))
        menu = saved.map { Array(NSOrderedSet(array: $0.map(\.rawValue))).compactMap { ($0 as? String).flatMap(Metric.init(rawValue:)) } } ?? [.cpu,.memory,.download,.upload]
        let rate = defaults.double(forKey: "interval")
        interval = [1.0,2.0,5.0,10.0].contains(rate) ? rate : 2
        appearance = defaults.string(forKey: "appearance") ?? "System"
        alertsEnabled = defaults.bool(forKey: "alertsEnabled")
        temperatureThreshold = defaults.object(forKey: "temperatureThreshold") as? Double ?? 90
        batteryThreshold = defaults.object(forKey: "batteryThreshold") as? Double ?? 15
        storageThreshold = defaults.object(forKey: "storageThreshold") as? Double ?? 10
        let processRate = defaults.double(forKey: "processInterval")
        processInterval = [1.0, 2.0, 5.0, 10.0].contains(processRate) ? processRate : 2
        let processLimit = defaults.integer(forKey: "processTopLimit")
        processTopLimit = [20, 50].contains(processLimit) ? processLimit : 20
        showSystemProcesses = defaults.object(forKey: "showSystemProcesses") as? Bool ?? false
    }
    func toggle(_ metric: Metric) { if menu.contains(metric) { menu.removeAll { $0 == metric } } else { menu.append(metric) } }
    func move(_ metric: Metric, by offset: Int) {
        guard let i = menu.firstIndex(of: metric), menu.indices.contains(i+offset) else { return }
        menu.swapAt(i,i+offset)
    }
    func setLogin(_ enabled: Bool) {
        do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; loginMessage = "" }
        catch { loginMessage = error.localizedDescription }
    }
}
