import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var engine: SamplingEngine
    @State private var tab = "Menu Bar"
    var body: some View {
        TabView(selection: $tab) {
            menuSettings.tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }.tag("Menu Bar")
            generalSettings.tabItem { Label("General", systemImage: "gearshape") }.tag("General")
            alertSettings.tabItem { Label("Alerts", systemImage: "bell") }.tag("Alerts")
        }.padding(20).frame(width: 590, height: 610).preferredColorScheme(preferences.colorScheme)
    }
    private var menuSettings: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Your Mac, at a glance").font(.title2.weight(.semibold))
            Text("Choose the readings you want to keep in sight. Use the arrows to change their order.").foregroundStyle(.secondary)
            HStack { Image(systemName: "waveform.path.ecg"); Text(engine.menuText.isEmpty ? "MacPulse" : engine.menuText).font(.system(size: 12, weight: .medium, design: .monospaced)).lineLimit(1) }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(preferences.menu + Metric.menuChoices.filter { !preferences.menu.contains($0) }) { metric in
                        HStack {
                            Toggle(isOn: Binding(get: { preferences.menu.contains(metric) }, set: { _ in preferences.toggle(metric) })) { Label(metric.title, systemImage: metric.symbol) }.toggleStyle(.checkbox).accessibilityIdentifier("toggle-\(metric.rawValue)")
                            Spacer()
                            if preferences.menu.contains(metric) {
                                Button { preferences.move(metric, by: -1) } label: { Image(systemName: "chevron.up") }.disabled(preferences.menu.first == metric).help(L10n.format("Move %@ earlier", metric.title)).accessibilityIdentifier("up-\(metric.rawValue)")
                                Button { preferences.move(metric, by: 1) } label: { Image(systemName: "chevron.down") }.disabled(preferences.menu.last == metric).help(L10n.format("Move %@ later", metric.title)).accessibilityIdentifier("down-\(metric.rawValue)")
                            }
                        }.padding(.vertical, 9)
                        Divider()
                    }
                }
            }
            Text("The menu bar uses a compact width budget. Extra selections appear as +N; all remain available in the panel. Turn every reading off for an icon-only menu item.").font(.caption).foregroundStyle(.secondary)
        }.padding(.top, 16)
    }
    private var generalSettings: some View {
        Form {
            Section("Sampling") {
                Picker("Update every", selection: $preferences.interval) { ForEach([1.0,2.0,5.0,10.0], id: \.self) { Text(L10n.format("%d seconds", Int($0))).tag($0) } }.accessibilityIdentifier("sampling-interval")
                Text("2 seconds is a balanced default. Static information and Wi-Fi refresh every 15 samples. Sampling pauses during sleep.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Appearance") { Picker("Theme", selection: $preferences.appearance) { ForEach(["System","Light","Dark"], id: \.self) { Text(L10n.text($0)).tag($0) } } }
            Section("Processes") {
                Picker("Process update every", selection: $preferences.processInterval) {
                    ForEach([1.0, 2.0, 5.0, 10.0], id: \.self) { Text(L10n.format("%d seconds", Int($0))).tag($0) }
                }
                Picker("Top processes", selection: $preferences.processTopLimit) {
                    Text(L10n.text("Top 20")).tag(20)
                    Text(L10n.text("Top 50")).tag(50)
                    Text(L10n.text("All")).tag(0)
                }
                Toggle("Show system processes by default", isOn: $preferences.showSystemProcesses)
            }
            Section("Language") {
                Text(L10n.text("MacPulse follows the per-app language selected in macOS System Settings."))
                Text(L10n.format("Current language: %@", Locale.current.localizedString(forLanguageCode: Locale.current.language.languageCode?.identifier ?? "en") ?? "English")).font(.caption).foregroundStyle(.secondary)
                Button("Open Language & Region Settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension")!) }
                Text("Restart MacPulse after changing the per-app language.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Startup") {
                Toggle("Launch at Login", isOn: Binding(get: { SMAppService.mainApp.status == .enabled }, set: { preferences.setLogin($0) }))
                if SMAppService.mainApp.status == .requiresApproval { Text("macOS approval is required in Login Items.").font(.caption) }
                if !preferences.loginMessage.isEmpty { Text(preferences.loginMessage).font(.caption).foregroundStyle(.secondary) }
            }
            Section("Desktop widget") { Text("Add MacPulse from the macOS widget gallery. Widgets show timestamped snapshots and follow the system refresh budget; the menu bar provides live readings."); Text(engine.widgetStatus).font(.caption).foregroundStyle(.secondary) }
            Section("Privacy & history") { Text("All metrics stay on this Mac. History is limited to 900 samples and 30 minutes, and is cleared when MacPulse quits.") }
        }.formStyle(.grouped)
    }
    private var alertSettings: some View {
        Form {
            Section("Notifications") {
                Toggle("Enable alerts", isOn: $preferences.alertsEnabled).onChange(of: preferences.alertsEnabled) { _, enabled in if enabled { engine.alerts.requestPermission() } }
                Text("Conditions must persist for 30 seconds. At most one notification per condition per hour. Alerts are off by default.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Thresholds") {
                Stepper(L10n.format("CPU temperature: %d°C", Int(preferences.temperatureThreshold)), value: $preferences.temperatureThreshold, in: 60...110, step: 5)
                Stepper(L10n.format("Low battery: %d%%", Int(preferences.batteryThreshold)), value: $preferences.batteryThreshold, in: 5...40, step: 5)
                Stepper(L10n.format("Free storage below: %d GB", Int(preferences.storageThreshold)), value: $preferences.storageThreshold, in: 5...100, step: 5)
                Text("Memory alerts use critical macOS memory pressure, not a percentage threshold.").font(.caption).foregroundStyle(.secondary)
            }.disabled(!preferences.alertsEnabled)
            Section("Permission") { AlertPermissionView(alerts: engine.alerts) }
        }.formStyle(.grouped)
    }
}
private struct AlertPermissionView: View {
    @ObservedObject var alerts: AlertEngine
    var body: some View { Text(alerts.permission).font(.callout).foregroundStyle(.secondary) }
}
