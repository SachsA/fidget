import SwiftUI
import FidgetCore

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    private static let intervalPresets: [TimeInterval] = [15, 30, 60, 120, 180, 240]

    var body: some View {
        Form {
            Section("General") {
                Toggle("Active", isOn: $model.settings.enabled)
                Toggle("Launch at login", isOn: $model.settings.launchAtLogin)
                Toggle("Keep the display awake", isOn: $model.settings.preventSleep)
            }

            Section {
                Picker("Nudge after", selection: $model.settings.idleInterval) {
                    ForEach(intervalOptions, id: \.self) { Text(Self.format($0)).tag($0) }
                }
                Picker("Movement", selection: $model.settings.mode) {
                    Text("Visible").tag(JiggleMode.visible)
                    Text("Zen (cursor stays still)").tag(JiggleMode.zen)
                }
                if model.settings.mode == .visible {
                    Stepper(value: $model.settings.distance, in: FidgetSettings.distanceRange) {
                        Text("Distance: \(model.settings.distance) px")
                    }
                }
            } header: {
                Text("Movement")
            } footer: {
                Text("Fidget only moves the mouse when you have been inactive for the chosen duration.")
                    .foregroundStyle(.secondary)
            }

            Section("Schedule") {
                Toggle("Only during working hours", isOn: $model.settings.schedule.enabled)
                if model.settings.schedule.enabled {
                    DayPicker(days: $model.settings.schedule.days)
                    DatePicker("From", selection: minuteBinding(\.startMinute), displayedComponents: .hourAndMinute)
                    DatePicker("To", selection: minuteBinding(\.endMinute), displayedComponents: .hourAndMinute)
                }
            }

            Section("Keyboard shortcut") {
                Toggle("Toggle Fidget from anywhere", isOn: $model.settings.hotkeyEnabled)
                if model.settings.hotkeyEnabled {
                    LabeledContent("Shortcut") {
                        HotkeyRecorder(hotkey: $model.settings.hotkey) { model.suspendHotkey($0) }
                    }
                }
            }

            Section("Permissions") {
                TimelineView(.periodic(from: .now, by: 2)) { _ in
                    if Accessibility.isTrusted {
                        Label("Accessibility access granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        HStack {
                            Label("Accessibility access needed", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Spacer()
                            Button("Open Settings") { model.openAccessibilitySettings() }
                        }
                    }
                }
            }

            Section {
                LabeledContent("Version", value: FidgetInfo.version)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var intervalOptions: [TimeInterval] {
        Array(Set(Self.intervalPresets + [model.settings.idleInterval])).sorted()
    }

    private static func format(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        if s < 60 { return "\(s) seconds" }
        if s % 60 == 0 { return s == 60 ? "1 minute" : "\(s / 60) minutes" }
        return "\(s / 60) min \(s % 60) s"
    }

    private func minuteBinding(_ keyPath: WritableKeyPath<Schedule, Int>) -> Binding<Date> {
        Binding(
            get: {
                let m = model.settings.schedule[keyPath: keyPath]
                return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                model.settings.schedule[keyPath: keyPath] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
    }
}

/// One toggle button per weekday, Monday first.
struct DayPicker: View {
    @Binding var days: Set<Int>

    var body: some View {
        LabeledContent("Days") {
            HStack(spacing: 4) {
                ForEach(Schedule.weekOrder, id: \.self) { day in
                    let selected = days.contains(day)
                    Button {
                        if selected { days.remove(day) } else { days.insert(day) }
                    } label: {
                        Text(Calendar.current.veryShortWeekdaySymbols[day - 1])
                            .frame(width: 22, height: 22)
                            .background(selected ? Color.accentColor : Color.secondary.opacity(0.15), in: Circle())
                            .foregroundStyle(selected ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Click, then press the new combination. Escape cancels.
struct HotkeyRecorder: View {
    @Binding var hotkey: Hotkey
    var onRecordingChange: (Bool) -> Void

    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? "Press keys…" : hotkey.displayString) {
            recording ? stop() : start()
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        onRecordingChange(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape
                stop()
            } else if let new = Hotkey(event: event) {
                hotkey = new
                stop()
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording {
            recording = false
            onRecordingChange(false)
        }
    }
}
