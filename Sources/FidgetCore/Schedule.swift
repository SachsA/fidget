import Foundation

/// Restricts Fidget to some days and hours. Weekdays use `Calendar` numbering: 1 = Sunday ... 7 = Saturday.
public struct Schedule: Codable, Equatable {
    public var enabled: Bool
    public var days: Set<Int>
    /// Minutes since midnight.
    public var startMinute: Int
    public var endMinute: Int

    public init(enabled: Bool, days: Set<Int>, startMinute: Int, endMinute: Int) {
        self.enabled = enabled
        self.days = days
        self.startMinute = startMinute
        self.endMinute = endMinute
    }

    /// Monday to Friday, 9:00 to 18:00 (disabled by default).
    public static let workHours = Schedule(enabled: false, days: [2, 3, 4, 5, 6], startMinute: 9 * 60, endMinute: 18 * 60)

    /// Display order, Monday first.
    public static let weekOrder = [2, 3, 4, 5, 6, 7, 1]

    public func isActive(at date: Date, calendar: Calendar = .current) -> Bool {
        guard enabled else { return true }
        let c = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = c.weekday, let hour = c.hour, let minute = c.minute else { return true }
        let now = hour * 60 + minute

        if startMinute == endMinute {
            return days.contains(weekday)
        }
        if startMinute < endMinute {
            return days.contains(weekday) && now >= startMinute && now < endMinute
        }
        // Overnight range (e.g. 22:00-06:00): the part after midnight belongs to the previous day.
        if now >= startMinute { return days.contains(weekday) }
        if now < endMinute { return days.contains(weekday == 1 ? 7 : weekday - 1) }
        return false
    }

    // MARK: Text format used by the CLI

    private static let dayNames = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]

    /// Parses "mon-fri", "mon,wed,fri", "sat-sun", "weekdays", "weekend" or "everyday".
    public static func parseDays(_ text: String) -> Set<Int>? {
        let t = text.lowercased().trimmingCharacters(in: .whitespaces)
        switch t {
        case "weekdays": return [2, 3, 4, 5, 6]
        case "weekend": return [7, 1]
        case "everyday", "all": return Set(1...7)
        default: break
        }
        var result = Set<Int>()
        for part in t.split(separator: ",") {
            let bounds = part.split(separator: "-").map { String($0).trimmingCharacters(in: .whitespaces) }
            guard (1...2).contains(bounds.count) else { return nil }
            guard let a = index(of: bounds[0]) else { return nil }
            guard bounds.count == 2 else { result.insert(a + 1); continue }
            guard let b = index(of: bounds[1]) else { return nil }
            var i = a
            while true {
                result.insert(i + 1)
                if i == b { break }
                i = (i + 1) % 7
            }
        }
        return result.isEmpty ? nil : result
    }

    private static func index(of name: String) -> Int? {
        dayNames.firstIndex { name.hasPrefix($0) && name.count >= 3 }
    }

    /// Parses "09:00-18:00" (or "9-18") into minutes since midnight.
    public static func parseHours(_ text: String) -> (start: Int, end: Int)? {
        let parts = text.split(separator: "-")
        guard parts.count == 2, let a = parseTime(String(parts[0])), let b = parseTime(String(parts[1])) else { return nil }
        return (a, b)
    }

    public static func parseTime(_ text: String) -> Int? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard (1...2).contains(parts.count), let h = Int(parts[0]), (0...23).contains(h) else { return nil }
        let m = parts.count == 2 ? Int(parts[1]) : 0
        guard let m, (0...59).contains(m) else { return nil }
        return h * 60 + m
    }

    public static func formatTime(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    public var daysDescription: String {
        Self.weekOrder.filter { days.contains($0) }.map { Self.dayNames[$0 - 1] }.joined(separator: ",")
    }

    public var hoursDescription: String {
        "\(Self.formatTime(startMinute))-\(Self.formatTime(endMinute))"
    }
}
