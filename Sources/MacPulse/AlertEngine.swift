import Foundation
import UserNotifications

struct AlertEvent: Identifiable, Equatable { var id: String; var title: String; var message: String }
struct AlertPolicy {
    private var since: [String: Date] = [:]
    private(set) var sent: [String: Date]
    init(lastSent: [String: Date] = [:]) { sent = lastSent }
    mutating func resetConditions() { since.removeAll() }
    mutating func evaluate(_ snapshot: Snapshot, temperature: Double, battery: Double, storage: Double) -> [AlertEvent] {
        let rules: [(String, Bool, String, String)] = [
            ("temperature", (snapshot[.cpuTemperature] ?? 0) >= temperature, L10n.text("High CPU temperature"), L10n.format("CPU sensors have remained above %d°C for 30 seconds.", Int(temperature))),
            ("memory", snapshot.values["pressure"] == 4, L10n.text("Critical memory pressure"), L10n.text("macOS reports sustained critical memory pressure.")),
            ("battery", snapshot[.battery].map { $0 <= battery } == true && snapshot.values["externalPower"] == 0, L10n.text("Low battery"), L10n.format("Battery is at or below %d%%. Connect power when convenient.", Int(battery))),
            ("storage", snapshot[.storageAvailable].map { $0 < storage * 1e9 } == true, L10n.text("Low storage"), L10n.format("Less than %d GB remains on the system data volume.", Int(storage)))
        ]
        var events: [AlertEvent] = []
        for (id, triggered, title, message) in rules {
            guard triggered else { since[id] = nil; continue }
            if since[id] == nil { since[id] = snapshot.date }
            if snapshot.date.timeIntervalSince(since[id]!) >= 30 && snapshot.date.timeIntervalSince(sent[id] ?? .distantPast) >= 3600 {
                events.append(AlertEvent(id: id, title: title, message: message)); sent[id] = snapshot.date
            }
        }
        return events
    }
}

struct HealthAlertPolicy {
    private var active: [String: HealthSeverity] = [:]
    private var recoverySince: [String: Date] = [:]
    private(set) var sent: [String: Date]

    init(lastSent: [String: Date] = [:]) { sent = lastSent }

    mutating func resetConditions() {
        active.removeAll()
        recoverySince.removeAll()
    }

    mutating func evaluate(_ health: MacHealthSnapshot) -> [AlertEvent] {
        let significant = health.activeIssues.filter { $0.severity >= .high }
        let current = Set(significant.map(\.id))
        var events: [AlertEvent] = []
        for issue in significant {
            recoverySince[issue.id] = nil
            active[issue.id] = issue.severity
            let eventID = "health.\(issue.id)"
            guard health.timestamp.timeIntervalSince(sent[eventID] ?? .distantPast) >= 3600 else { continue }
            let root = issue.rootCause.map { L10n.format("health.alert.rootCause", $0.name) } ?? ""
            events.append(.init(id: eventID, title: L10n.text("health.alert.highLoad"), message: [issue.summary, root].filter { !$0.isEmpty }.joined(separator: " ")))
            sent[eventID] = health.timestamp
        }
        for (id, severity) in active where !current.contains(id) && severity >= .high {
            if recoverySince[id] == nil { recoverySince[id] = health.timestamp }
            guard health.timestamp.timeIntervalSince(recoverySince[id]!) >= HealthThresholds.recoveryDuration else { continue }
            let eventID = "health.recovered.\(id)"
            if health.timestamp.timeIntervalSince(sent[eventID] ?? .distantPast) >= 3600 {
                events.append(.init(id: eventID, title: L10n.text("health.alert.backToNormal"), message: L10n.text("health.alert.recoveredSummary")))
                sent[eventID] = health.timestamp
            }
            active[id] = nil
            recoverySince[id] = nil
        }
        return events
    }
}

@MainActor final class AlertEngine: ObservableObject {
    @Published var permission = L10n.text("Notifications are off by default")
    @Published var recent: [AlertEvent] = []
    private var policy = AlertPolicy(lastSent: UserDefaults.standard.dictionary(forKey: "alertLastSent") as? [String: Date] ?? [:])
    private var healthPolicy = HealthAlertPolicy(lastSent: UserDefaults.standard.dictionary(forKey: "healthAlertLastSent") as? [String: Date] ?? [:])
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] allowed, error in
            Task { @MainActor in self?.permission = error?.localizedDescription ?? (allowed ? L10n.text("Notifications allowed") : L10n.text("Notifications not allowed in macOS Settings")) }
        }
    }
    func evaluate(_ snapshot: Snapshot, health: MacHealthSnapshot, preferences: Preferences) {
        guard preferences.alertsEnabled else { policy.resetConditions(); healthPolicy.resetConditions(); return }
        let lowBattery = policy.evaluate(snapshot, temperature: preferences.temperatureThreshold, battery: preferences.batteryThreshold, storage: preferences.storageThreshold).filter { $0.id == "battery" }
        for event in lowBattery + healthPolicy.evaluate(health) {
            recent.insert(event, at: 0); recent = Array(recent.prefix(10))
            let content = UNMutableNotificationContent(); content.title = event.title; content.body = event.message
            UserDefaults.standard.set(policy.sent, forKey: "alertLastSent")
            UserDefaults.standard.set(healthPolicy.sent, forKey: "healthAlertLastSent")
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: event.id, content: content, trigger: nil)) { [weak self] error in
                if let error { Task { @MainActor in self?.permission = error.localizedDescription } }
            }
        }
    }
}
