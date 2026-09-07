import Foundation
import UserNotifications

struct AlertEvent: Identifiable { var id: String; var title: String; var message: String }
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
@MainActor final class AlertEngine: ObservableObject {
    @Published var permission = L10n.text("Notifications are off by default")
    @Published var recent: [AlertEvent] = []
    private var policy = AlertPolicy(lastSent: UserDefaults.standard.dictionary(forKey: "alertLastSent") as? [String: Date] ?? [:])
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] allowed, error in
            Task { @MainActor in self?.permission = error?.localizedDescription ?? (allowed ? L10n.text("Notifications allowed") : L10n.text("Notifications not allowed in macOS Settings")) }
        }
    }
    func evaluate(_ snapshot: Snapshot, preferences: Preferences) {
        guard preferences.alertsEnabled else { policy.resetConditions(); return }
        for event in policy.evaluate(snapshot, temperature: preferences.temperatureThreshold, battery: preferences.batteryThreshold, storage: preferences.storageThreshold) {
            recent.insert(event, at: 0); recent = Array(recent.prefix(10))
            let content = UNMutableNotificationContent(); content.title = event.title; content.body = event.message
            UserDefaults.standard.set(policy.sent, forKey: "alertLastSent")
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: event.id, content: content, trigger: nil)) { [weak self] error in
                if let error { Task { @MainActor in self?.permission = error.localizedDescription } }
            }
        }
    }
}
