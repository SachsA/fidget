import AppKit
import Carbon.HIToolbox
import ServiceManagement
import FidgetCore

/// Registers one system-wide shortcut through Carbon (works without any extra permission).
final class HotkeyManager {
    var onPress: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { manager.onPress?() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    func register(_ hotkey: Hotkey?) {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        guard let hotkey else { return }
        let id = EventHotKeyID(signature: OSType(0x4644_4754), id: 1) // "FDGT"
        RegisterEventHotKey(hotkey.keyCode, hotkey.carbonModifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}

extension Hotkey {
    /// Builds a hotkey from a key press. Requires at least one of ⌃ ⌥ ⌘.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var mods: UInt32 = 0
        if flags.contains(.control) { mods |= Hotkey.control }
        if flags.contains(.option) { mods |= Hotkey.option }
        if flags.contains(.shift) { mods |= Hotkey.shift }
        if flags.contains(.command) { mods |= Hotkey.cmd }
        guard mods & (Hotkey.control | Hotkey.option | Hotkey.cmd) != 0 else { return nil }
        let code = UInt32(event.keyCode)
        let label = Hotkey.specialKeys[code]
            ?? event.charactersIgnoringModifiers?.uppercased()
            ?? "?"
        self.init(keyCode: code, carbonModifiers: mods, keyLabel: label)
    }

    static let specialKeys: [UInt32: String] = [
        49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]
}

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Fidget: could not update login item: \(error.localizedDescription)")
        }
    }
}
