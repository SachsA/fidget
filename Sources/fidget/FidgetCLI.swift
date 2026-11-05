import Foundation
import FidgetCore

@main
struct FidgetCLI {
    static let usage = """
    fidget \(FidgetInfo.version): keeps your Mac awake and your status green.

    USAGE
      fidget [run] [options]        Run in the foreground (Ctrl+C to stop)
      fidget config                 Show saved settings (shared with Fidget.app)
      fidget config set KEY VALUE   Change a saved setting
      fidget config reset           Restore default settings
      fidget jiggle                 Nudge the mouse once, right now
      fidget --version | --help

    RUN OPTIONS (override saved settings for this run only)
      -i, --interval SECONDS        Inactivity before a nudge (5-3600)
      -d, --distance PIXELS         Movement size in visible mode (1-50)
      -z, --zen                     Invisible movement, the cursor stays still
          --visible                 Visible movement
          --allow-sleep             Do not prevent display sleep
          --ignore-schedule         Run regardless of the schedule
      -q, --quiet                   No log output

    CONFIG KEYS
      interval SECONDS              distance PIXELS
      mode visible|zen              prevent-sleep on|off
      schedule on|off               days mon-fri | mon,wed,fri | weekdays | weekend | everyday
      hours 09:00-18:00             enabled on|off

    Fidget needs Accessibility access for the app running it (your terminal for the CLI):
    System Settings > Privacy & Security > Accessibility.
    """

    @MainActor
    static func main() {
        var args = Array(CommandLine.arguments.dropFirst())
        let command = args.first.map { $0.hasPrefix("-") ? "run" : $0 } ?? "run"
        if args.first == command { args.removeFirst() }

        switch command {
        case "run": run(args)
        case "config": config(args)
        case "jiggle": jiggleOnce()
        case "help", "--help", "-h": print(usage)
        case "version", "--version", "-v": print(FidgetInfo.version)
        default: fail("unknown command '\(command)'. See 'fidget --help'.")
        }
    }

    // MARK: run

    @MainActor
    static func run(_ args: [String]) {
        if args.contains("--help") || args.contains("-h") { print(usage); return }
        if args.contains("--version") || args.contains("-v") { print(FidgetInfo.version); return }

        var settings = SettingsStore().load()
        settings.enabled = true
        var quiet = false
        var it = args.makeIterator()
        while let arg = it.next() {
            switch arg {
            case "-i", "--interval":
                guard let v = it.next().flatMap(TimeInterval.init) else { fail("\(arg) expects a number of seconds") }
                settings.idleInterval = v
            case "-d", "--distance":
                guard let v = it.next().flatMap(Int.init) else { fail("\(arg) expects a number of pixels") }
                settings.distance = v
            case "-z", "--zen": settings.mode = .zen
            case "--visible": settings.mode = .visible
            case "--allow-sleep": settings.preventSleep = false
            case "--ignore-schedule": settings.schedule.enabled = false
            case "-q", "--quiet": quiet = true
            default: fail("unknown option '\(arg)'. See 'fidget --help'.")
            }
        }
        settings = settings.clamped()

        setvbuf(stdout, nil, _IONBF, 0)
        if !Accessibility.isTrusted {
            Accessibility.request()
            printErr("Accessibility access is missing for this terminal. Grant it in System Settings > Privacy & Security > Accessibility; Fidget starts nudging as soon as it is granted.")
        }

        let jiggler = Jiggler(settings: settings)
        let log: (String) -> Void = { message in
            guard !quiet else { return }
            print("[\(timestamp())] \(message)")
        }
        jiggler.onJiggle = { _ in log("nudged the mouse") }
        jiggler.onStateChange = { state in
            switch state {
            case .active: log("active: nudging after \(Int(settings.idleInterval))s of inactivity (\(settings.mode.rawValue) mode)")
            case .outsideSchedule: log("paused: outside schedule \(settings.schedule.daysDescription) \(settings.schedule.hoursDescription)")
            case .missingPermission: log("waiting for Accessibility access")
            case .disabled: break
            }
        }
        if !quiet { print("Fidget \(FidgetInfo.version) running. Ctrl+C to stop.") }
        jiggler.start()
        withExtendedLifetime(jiggler) { RunLoop.main.run() }
    }

    @MainActor
    static func jiggleOnce() {
        guard Accessibility.isTrusted else {
            Accessibility.request()
            fail("Accessibility access is missing for this terminal.")
        }
        Jiggler(settings: SettingsStore().load()).jiggle()
    }

    // MARK: config

    static func config(_ args: [String]) {
        let store = SettingsStore()
        guard let sub = args.first else { return printSettings(store.load()) }

        switch sub {
        case "reset":
            store.save(FidgetSettings())
            printSettings(FidgetSettings())
        case "set":
            guard args.count == 3 else { fail("usage: fidget config set KEY VALUE") }
            var s = store.load()
            apply(key: args[1], value: args[2], to: &s)
            store.save(s)
            printSettings(store.load())
        default:
            fail("unknown config command '\(sub)'. Use 'set' or 'reset'.")
        }
    }

    static func apply(key: String, value: String, to s: inout FidgetSettings) {
        switch key {
        case "interval":
            guard let v = TimeInterval(value) else { fail("interval expects seconds") }
            s.idleInterval = v
        case "distance":
            guard let v = Int(value) else { fail("distance expects pixels") }
            s.distance = v
        case "mode":
            guard let m = JiggleMode(rawValue: value) else { fail("mode expects 'visible' or 'zen'") }
            s.mode = m
        case "prevent-sleep": s.preventSleep = parseBool(value, key)
        case "schedule": s.schedule.enabled = parseBool(value, key)
        case "enabled": s.enabled = parseBool(value, key)
        case "days":
            guard let d = Schedule.parseDays(value) else { fail("days expects e.g. mon-fri, mon,wed,fri, weekdays, weekend, everyday") }
            s.schedule.days = d
        case "hours":
            guard let h = Schedule.parseHours(value) else { fail("hours expects HH:MM-HH:MM, e.g. 09:00-18:00") }
            s.schedule.startMinute = h.start
            s.schedule.endMinute = h.end
        default:
            fail("unknown key '\(key)'. See 'fidget --help'.")
        }
    }

    static func parseBool(_ value: String, _ key: String) -> Bool {
        switch value.lowercased() {
        case "on", "true", "yes", "1": return true
        case "off", "false", "no", "0": return false
        default: fail("\(key) expects on or off")
        }
    }

    static func printSettings(_ s: FidgetSettings) {
        let onOff: (Bool) -> String = { $0 ? "on" : "off" }
        print("""
        enabled        \(onOff(s.enabled))
        interval       \(Int(s.idleInterval))s
        mode           \(s.mode.rawValue)
        distance       \(s.distance)px
        prevent-sleep  \(onOff(s.preventSleep))
        schedule       \(onOff(s.schedule.enabled)) (\(s.schedule.daysDescription) \(s.schedule.hoursDescription))
        hotkey         \(s.hotkeyEnabled ? s.hotkey.displayString : "off") (app only)
        launch-at-login \(onOff(s.launchAtLogin)) (app only)
        """)
    }

    // MARK: helpers

    static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }

    static func printErr(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    static func fail(_ message: String) -> Never {
        printErr("fidget: \(message)")
        exit(1)
    }
}
