import SwiftUI
import FidgetCore

@main
struct FidgetApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(model)
        } label: {
            Image(systemName: model.statusSymbol)
        }
        .menuBarExtraStyle(.menu)
    }
}

struct MenuContent: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Toggle("Active", isOn: $model.settings.enabled)

        Text(model.statusText)

        if model.state == .missingPermission {
            Button("Grant Accessibility Access…") { model.openAccessibilitySettings() }
        }

        Divider()

        Button("Nudge Now") { model.jiggleNow() }
        Button("Settings…") { SettingsWindow.show(model: model) }
            .keyboardShortcut(",")

        Divider()

        Button("Quit Fidget") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show(model: AppModel) {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView().environmentObject(model))
            let w = NSWindow(contentViewController: host)
            w.title = "Fidget Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
