import Foundation

public enum FidgetInfo {
    public static let version = "0.1.0"
    public static let bundleIdentifier = "io.github.sachsa.fidget"
}

public enum JiggleMode: String, Codable, CaseIterable {
    /// Moves the cursor by `distance` pixels and back.
    case visible
    /// Sends a movement event at the current position: the cursor never moves on screen.
    case zen
}

/// A global keyboard shortcut, stored with Carbon key code and modifier flags.
public struct Hotkey: Codable, Equatable {
    public var keyCode: UInt32
    public var carbonModifiers: UInt32
    public var keyLabel: String

    public init(keyCode: UInt32, carbonModifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.keyLabel = keyLabel
    }

    // Carbon modifier bits (Carbon.HIToolbox), duplicated here so the core does not depend on Carbon.
    public static let cmd: UInt32 = 1 << 8
    public static let shift: UInt32 = 1 << 9
    public static let option: UInt32 = 1 << 11
    public static let control: UInt32 = 1 << 12

    /// Control + Option + Command + J
    public static let `default` = Hotkey(keyCode: 38, carbonModifiers: control | option | cmd, keyLabel: "J")

    public var displayString: String {
        var s = ""
        if carbonModifiers & Self.control != 0 { s += "⌃" }
        if carbonModifiers & Self.option != 0 { s += "⌥" }
        if carbonModifiers & Self.shift != 0 { s += "⇧" }
        if carbonModifiers & Self.cmd != 0 { s += "⌘" }
        return s + keyLabel
    }
}

public struct FidgetSettings: Codable, Equatable {
    public var enabled = true
    /// Seconds of user inactivity before Fidget nudges the mouse.
    public var idleInterval: TimeInterval = 60
    /// Pixels moved in visible mode.
    public var distance = 1
    public var mode: JiggleMode = .visible
    /// Keeps the display (and the Mac) from sleeping while Fidget is active.
    public var preventSleep = true
    public var schedule: Schedule = .workHours
    public var launchAtLogin = false
    public var hotkeyEnabled = true
    public var hotkey: Hotkey = .default

    public static let idleRange: ClosedRange<TimeInterval> = 5...3600
    public static let distanceRange: ClosedRange<Int> = 1...50

    public init() {}

    /// Returns a copy with every value brought back into its valid range.
    public func clamped() -> FidgetSettings {
        var s = self
        s.idleInterval = min(max(idleInterval, Self.idleRange.lowerBound), Self.idleRange.upperBound)
        s.distance = min(max(distance, Self.distanceRange.lowerBound), Self.distanceRange.upperBound)
        s.schedule.startMinute = min(max(schedule.startMinute, 0), 24 * 60 - 1)
        s.schedule.endMinute = min(max(schedule.endMinute, 0), 24 * 60 - 1)
        return s
    }

    // Tolerant decoding: any missing key falls back to its default, so older or partial
    // config files keep working when new settings are added.
    private enum CodingKeys: String, CodingKey {
        case enabled, idleInterval, distance, mode, preventSleep, schedule, launchAtLogin, hotkeyEnabled, hotkey
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = FidgetSettings()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        idleInterval = try c.decodeIfPresent(TimeInterval.self, forKey: .idleInterval) ?? d.idleInterval
        distance = try c.decodeIfPresent(Int.self, forKey: .distance) ?? d.distance
        mode = (try? c.decodeIfPresent(JiggleMode.self, forKey: .mode)) ?? d.mode
        preventSleep = try c.decodeIfPresent(Bool.self, forKey: .preventSleep) ?? d.preventSleep
        schedule = (try? c.decodeIfPresent(Schedule.self, forKey: .schedule)) ?? d.schedule
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
        hotkeyEnabled = try c.decodeIfPresent(Bool.self, forKey: .hotkeyEnabled) ?? d.hotkeyEnabled
        hotkey = (try? c.decodeIfPresent(Hotkey.self, forKey: .hotkey)) ?? d.hotkey
    }
}

/// Persists settings in the shared preferences domain, so the app and the CLI see the same values.
public final class SettingsStore {
    public static let key = "settings"
    public static let didChangeNotification = Notification.Name("io.github.sachsa.fidget.settingsChanged")

    private let defaults: UserDefaults

    public init(defaults: UserDefaults? = nil) {
        if let defaults {
            self.defaults = defaults
        } else if Bundle.main.bundleIdentifier == FidgetInfo.bundleIdentifier {
            self.defaults = .standard
        } else {
            self.defaults = UserDefaults(suiteName: FidgetInfo.bundleIdentifier) ?? .standard
        }
    }

    public func load() -> FidgetSettings {
        guard let data = defaults.data(forKey: Self.key),
              let s = try? JSONDecoder().decode(FidgetSettings.self, from: data) else {
            return FidgetSettings()
        }
        return s.clamped()
    }

    public func save(_ settings: FidgetSettings) {
        guard let data = try? JSONEncoder().encode(settings.clamped()) else { return }
        defaults.set(data, forKey: Self.key)
        defaults.synchronize()
        DistributedNotificationCenter.default().postNotificationName(
            Self.didChangeNotification, object: nil, userInfo: nil, deliverImmediately: true)
    }
}
