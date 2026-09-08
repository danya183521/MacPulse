import SwiftUI
import AppKit

// Закрытие последнего окна скрывает Dashboard, но не завершает фоновый мониторинг.
final class MacPulseAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main struct MacPulseApp: App {
    @StateObject private var preferences: Preferences
    @StateObject private var engine: SamplingEngine
    @StateObject private var processMonitor: ProcessMonitor
    @StateObject private var status: StatusBarController
    @NSApplicationDelegateAdaptor(MacPulseAppDelegate.self) private var appDelegate
    init() {
        let preferences = Preferences()
        _preferences = StateObject(wrappedValue: preferences)
        let processMonitor = ProcessMonitor()
        processMonitor.startBackground()
        _processMonitor = StateObject(wrappedValue: processMonitor)
        let engine = SamplingEngine(preferences: preferences, processMonitor: processMonitor)
        _engine = StateObject(wrappedValue: engine)
        _status = StateObject(wrappedValue: StatusBarController(engine: engine, preferences: preferences))
    }
    var body: some Scene {
        Window("MacPulse", id: "dashboard") { DashboardContainer(engine: engine, preferences: preferences, processMonitor: processMonitor, status: status) }
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
    @ObservedObject var processMonitor: ProcessMonitor
    let status: StatusBarController
    @State private var selection: SectionPage? = .overview
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        DashboardView(engine: engine, preferences: preferences, processMonitor: processMonitor, selection: $selection).onAppear {
            status.openDashboard = { NSApp.activate(ignoringOtherApps: true); openWindow(id: "dashboard") }
            status.openHealth = { NSApp.activate(ignoringOtherApps: true); openWindow(id: "dashboard"); selection = .health }
            status.openSettings = { NSApp.activate(ignoringOtherApps: true); openSettings() }
        }
    }
}
struct MenuPanel: View {
    @ObservedObject var engine: SamplingEngine
    @ObservedObject var preferences: Preferences
    var dashboard: () -> Void
    var health: () -> Void
    var settings: () -> Void
    private var metrics: [Metric] {
        var result = preferences.menu
        for metric in [Metric.cpu,.cpuTemperature,.memory,.battery,.systemPower,.gpu,.download,.upload,.storage] where !result.contains(metric) { result.append(metric) }
        return result
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Label("MacPulse", systemImage: "waveform.path.ecg").font(.headline); Spacer(); Text(engine.snapshot.info["chip"] ?? L10n.text("Connecting…")).font(.caption).foregroundStyle(.secondary) }
            Button(action: health) {
                HStack(spacing: 12) {
                    Image(systemName: "gauge.with.dots.needle.67percent").font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.text("health.title")).font(.headline)
                        Text(engine.healthSnapshot.overallTitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(engine.healthSnapshot.overallScore)").font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
                }
                .padding(12)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("panel-health")
                ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()),GridItem(.flexible())], spacing: 12) {
                ForEach(metrics) { metric in
                    let value = metric == .health ? "\(engine.healthSnapshot.overallScore)" : metric.format(engine.snapshot[metric])
                    VStack(alignment: .leading, spacing: 5) { Label(metric.title, systemImage: metric.symbol).font(.caption).foregroundStyle(.secondary); Text(value).font(.system(size: 20, weight: .medium, design: .rounded)).monospacedDigit() }.frame(maxWidth: .infinity, alignment: .leading).padding(10).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 9)).help(metric == .health ? engine.healthSnapshot.summary : (engine.snapshot[metric] == nil ? engine.snapshot.reason(for: metric) : metric.source))
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
