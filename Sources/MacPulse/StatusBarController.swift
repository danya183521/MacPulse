import AppKit
import SwiftUI
import Combine

// AppKit даёт точную ширину пункта и доступную с клавиатуры нативную панель.
@MainActor final class StatusBarController: NSObject, ObservableObject, NSPopoverDelegate {
    let item: NSStatusItem
    private let popover = NSPopover()
    private let engine: SamplingEngine
    private let preferences: Preferences
    private var subscriptions = Set<AnyCancellable>()
    var openDashboard: (() -> Void)?
    var openHealth: (() -> Void)?
    var openSettings: (() -> Void)?
    init(engine: SamplingEngine, preferences: Preferences) {
        self.engine = engine; self.preferences = preferences
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: L10n.text("MacPulse"))
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            button.target = self; button.action = #selector(togglePanel)
            button.setAccessibilityIdentifier("macpulse-status-item")
        }
        popover.behavior = .transient
        popover.delegate = self
        engine.$snapshot.receive(on: RunLoop.main).sink { [weak self] _ in self?.updateTitle() }.store(in: &subscriptions)
        preferences.$menu.receive(on: RunLoop.main).sink { [weak self] _ in self?.updateTitle() }.store(in: &subscriptions)
        updateTitle()
    }
    private func updateTitle() {
        item.button?.title = engine.menuText.isEmpty ? "" : " " + engine.menuText
        item.button?.toolTip = L10n.text("MacPulse · Click for details")
        item.button?.setAccessibilityLabel(L10n.text("MacPulse") + " " + engine.menuText)
    }
    func popoverDidClose(_ notification: Notification) { popover.contentViewController = nil }
    func shutdown() { subscriptions.removeAll(); popover.performClose(nil); NSStatusBar.system.removeStatusItem(item) }
    @objc func togglePanel() {
        guard let button = item.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            popover.contentViewController = NSHostingController(rootView: MenuPanel(engine: engine, preferences: preferences, dashboard: { [weak self] in self?.popover.performClose(nil); self?.openDashboard?() }, health: { [weak self] in self?.popover.performClose(nil); self?.openHealth?() }, settings: { [weak self] in self?.popover.performClose(nil); self?.openSettings?() }))
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
