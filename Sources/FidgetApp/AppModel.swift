import SwiftUI
import FidgetCore

@MainActor
final class AppModel: ObservableObject {
    @Published var settings: FidgetSettings {
        didSet {
            guard settings != oldValue else { return }
            apply(previous: oldValue)
        }
    }
    @Published private(set) var state: EngineState = .disabled
    @Published private(set) var lastJiggle: Date?

    private let store = SettingsStore()
    private let jiggler: Jiggler
    private let hotkeys = HotkeyManager()
    private var observer: NSObjectProtocol?

    init() {
        var initial = store.load()
        initial.launchAtLogin = LoginItem.isEnabled
        settings = initial
        jiggler = Jiggler(settings: initial)

        jiggler.onStateChange = { [weak self] in self?.state = $0 }
        jiggler.onJiggle = { [weak self] in self?.lastJiggle = $0 }
        hotkeys.onPress = { [weak self] in self?.settings.enabled.toggle() }
        hotkeys.register(initial.hotkeyEnabled ? initial.hotkey : nil)

        // Picks up changes made with `fidget config set` while the app is running.
        observer = DistributedNotificationCenter.default().addObserver(
            forName: SettingsStore.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reloadFromStore() }
        }

        jiggler.start()
        if !Accessibility.isTrusted { Accessibility.request() }
    }

    private func apply(previous: FidgetSettings) {
        store.save(settings)
        jiggler.update(settings: settings)
        if settings.hotkeyEnabled != previous.hotkeyEnabled || settings.hotkey != previous.hotkey {
            hotkeys.register(settings.hotkeyEnabled ? settings.hotkey : nil)
        }
        if settings.launchAtLogin != LoginItem.isEnabled {
            LoginItem.set(settings.launchAtLogin)
            if settings.launchAtLogin != LoginItem.isEnabled {
                settings.launchAtLogin = LoginItem.isEnabled
            }
        }
    }

    private func reloadFromStore() {
        var fresh = store.load()
        fresh.launchAtLogin = LoginItem.isEnabled
        if fresh != settings { settings = fresh }
    }

    func jiggleNow() {
        jiggler.jiggle()
    }

    /// Temporarily disables the global shortcut, so the recorder can capture any combination.
    func suspendHotkey(_ suspended: Bool) {
        hotkeys.register(!suspended && settings.hotkeyEnabled ? settings.hotkey : nil)
    }

    func openAccessibilitySettings() {
        Accessibility.request()
        NSWorkspace.shared.open(Accessibility.settingsURL)
    }

    var statusSymbol: String {
        switch state {
        case .active: return "cursorarrow.motionlines"
        case .disabled: return "cursorarrow"
        case .outsideSchedule: return "moon.zzz"
        case .missingPermission: return "exclamationmark.triangle"
        }
    }

    var statusText: String {
        switch state {
        case .disabled:
            return "Paused"
        case .outsideSchedule:
            return "Sleeping until \(Schedule.formatTime(settings.schedule.startMinute))"
        case .missingPermission:
            return "Needs Accessibility access"
        case .active:
            guard let lastJiggle else { return "Watching for inactivity" }
            return "Last nudge at \(lastJiggle.formatted(date: .omitted, time: .shortened))"
        }
    }
}
