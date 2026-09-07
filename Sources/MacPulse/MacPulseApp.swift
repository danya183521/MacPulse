import SwiftUI
import AppKit

@main struct MacPulseApp: App {
    @StateObject private var preferences: Preferences
    @StateObject private var engine: SamplingEngine
    @StateObject private var status: StatusBarController
    init() {
        let preferences = Preferences()
        _preferences = StateObject(wrappedValue: preferences)
        let engine = SamplingEngine(preferences: preferences)
        _engine = StateObject(wrappedValue: engine)
        _status = StateObject(wrappedValue: StatusBarController(engine: engine, preferences: preferences))
    }
    var body: some Scene {
        Window("MacPulse", id: "dashboard") { DashboardContainer(engine: engine, preferences: preferences, status: status) }
            .defaultSize(width: 1100, height: 780)
            .commands {
                CommandGroup(after: .windowArrangement) {
                    Button(L10n.text("Show Quick Panel")) { status.togglePanel() }.keyboardShortcut("m", modifiers: [.command,.shift])
                }
            }
        Settings { SettingsView(preferences: preferences, engine: engine) }
    }
}
private struct DashboardContainer: View {
    @ObservedObject var engine: SamplingEngine
    @ObservedObject var preferences: Preferences
    let status: StatusBarController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        DashboardView(engine: engine, preferences: preferences).onAppear {
            status.openDashboard = { NSApp.activate(ignoringOtherApps: true); openWindow(id: "dashboard") }
            status.openSettings = { NSApp.activate(ignoringOtherApps: true); openSettings() }
        }
    }
}
struct MenuPanel: View {
    @ObservedObject var engine: SamplingEngine
    @ObservedObject var preferences: Preferences
    var dashboard: () -> Void
    var settings: () -> Void
    private var metrics: [Metric] {
        var result = preferences.menu
        for metric in [Metric.cpu,.cpuTemperature,.memory,.battery,.systemPower,.gpu,.download,.upload,.storage] where !result.contains(metric) { result.append(metric) }
        return result
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Label("MacPulse", systemImage: "waveform.path.ecg").font(.headline); Spacer(); Text(engine.snapshot.info["chip"] ?? L10n.text("Connecting…")).font(.caption).foregroundStyle(.secondary) }
            ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()),GridItem(.flexible())], spacing: 12) {
                ForEach(metrics) { metric in
                    VStack(alignment: .leading, spacing: 5) { Label(metric.title, systemImage: metric.symbol).font(.caption).foregroundStyle(.secondary); Text(metric.format(engine.snapshot[metric])).font(.system(size: 20, weight: .medium, design: .rounded)).monospacedDigit() }.frame(maxWidth: .infinity, alignment: .leading).padding(10).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 9)).help(engine.snapshot[metric] == nil ? engine.snapshot.reason(for: metric) : metric.source)
                }
            }
            }.frame(height: min(380, CGFloat((metrics.count + 1) / 2) * 76))
            HStack { Text(L10n.format("Thermals %@", engine.snapshot.thermalLabel.lowercased())); Spacer(); Text(engine.snapshot.date, style: .time) }.font(.caption).foregroundStyle(.secondary)
            Divider()
            HStack {
                Button(L10n.text("Dashboard")) { dashboard() }.keyboardShortcut("d").accessibilityIdentifier("panel-dashboard")
                Button { settings() } label: { Image(systemName: "gearshape") }.help(L10n.text("Settings")).accessibilityIdentifier("panel-settings")
                Spacer()
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }.help(L10n.text("Quit MacPulse"))
            }
        }.padding(18).frame(width: 360).preferredColorScheme(preferences.colorScheme)
    }
}
