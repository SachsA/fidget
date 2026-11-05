import XCTest
@testable import FidgetCore

final class ScheduleTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// 2026-11-02 is a Monday.
    private func date(day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    func testDisabledScheduleIsAlwaysActive() {
        var s = Schedule.workHours
        s.enabled = false
        XCTAssertTrue(s.isActive(at: date(day: 8, 3), calendar: calendar))
    }

    func testWorkHours() {
        var s = Schedule.workHours
        s.enabled = true
        XCTAssertTrue(s.isActive(at: date(day: 2, 9), calendar: calendar))
        XCTAssertTrue(s.isActive(at: date(day: 2, 17, 59), calendar: calendar))
        XCTAssertFalse(s.isActive(at: date(day: 2, 18), calendar: calendar))
        XCTAssertFalse(s.isActive(at: date(day: 2, 8, 59), calendar: calendar))
        XCTAssertFalse(s.isActive(at: date(day: 7, 10), calendar: calendar)) // Saturday
    }

    func testOvernightRangeBelongsToStartDay() {
        // Friday 22:00 to 06:00
        let s = Schedule(enabled: true, days: [6], startMinute: 22 * 60, endMinute: 6 * 60)
        XCTAssertTrue(s.isActive(at: date(day: 6, 23), calendar: calendar))   // Friday night
        XCTAssertTrue(s.isActive(at: date(day: 7, 5), calendar: calendar))    // Saturday early morning
        XCTAssertFalse(s.isActive(at: date(day: 7, 23), calendar: calendar))  // Saturday night
        XCTAssertFalse(s.isActive(at: date(day: 6, 5), calendar: calendar))   // Friday early morning
    }

    func testSameStartAndEndMeansWholeDay() {
        let s = Schedule(enabled: true, days: [2], startMinute: 0, endMinute: 0)
        XCTAssertTrue(s.isActive(at: date(day: 2, 15), calendar: calendar))
        XCTAssertFalse(s.isActive(at: date(day: 3, 15), calendar: calendar))
    }

    func testParseDays() {
        XCTAssertEqual(Schedule.parseDays("mon-fri"), [2, 3, 4, 5, 6])
        XCTAssertEqual(Schedule.parseDays("fri-mon"), [6, 7, 1, 2])
        XCTAssertEqual(Schedule.parseDays("Mon,wed,Friday"), [2, 4, 6])
        XCTAssertEqual(Schedule.parseDays("weekend"), [7, 1])
        XCTAssertEqual(Schedule.parseDays("everyday"), Set(1...7))
        XCTAssertNil(Schedule.parseDays("lundi"))
        XCTAssertNil(Schedule.parseDays(""))
    }

    func testParseHours() {
        XCTAssertEqual(Schedule.parseHours("09:00-18:30")?.start, 540)
        XCTAssertEqual(Schedule.parseHours("09:00-18:30")?.end, 1110)
        XCTAssertEqual(Schedule.parseHours("9-18")?.end, 1080)
        XCTAssertNil(Schedule.parseHours("25:00-18:00"))
        XCTAssertNil(Schedule.parseHours("9h-18h"))
    }

    func testDescriptions() {
        XCTAssertEqual(Schedule.workHours.daysDescription, "mon,tue,wed,thu,fri")
        XCTAssertEqual(Schedule.workHours.hoursDescription, "09:00-18:00")
    }
}

final class SettingsTests: XCTestCase {
    func testDecodingMissingKeysFallsBackToDefaults() throws {
        let json = #"{"idleInterval": 30, "mode": "zen"}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(FidgetSettings.self, from: json)
        XCTAssertEqual(s.idleInterval, 30)
        XCTAssertEqual(s.mode, .zen)
        XCTAssertEqual(s.distance, FidgetSettings().distance)
        XCTAssertEqual(s.hotkey, .default)
    }

    func testUnknownModeFallsBackToDefault() throws {
        let json = #"{"mode": "teleport"}"#.data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(FidgetSettings.self, from: json).mode, .visible)
    }

    func testClamping() {
        var s = FidgetSettings()
        s.idleInterval = 1
        s.distance = 500
        XCTAssertEqual(s.clamped().idleInterval, FidgetSettings.idleRange.lowerBound)
        XCTAssertEqual(s.clamped().distance, FidgetSettings.distanceRange.upperBound)
    }

    func testRoundTripThroughStore() {
        let defaults = UserDefaults(suiteName: "fidget-tests-\(UUID().uuidString)")!
        let store = SettingsStore(defaults: defaults)
        var s = FidgetSettings()
        s.idleInterval = 120
        s.schedule.enabled = true
        store.save(s)
        XCTAssertEqual(store.load(), s)
    }

    func testHotkeyDisplay() {
        XCTAssertEqual(Hotkey.default.displayString, "⌃⌥⌘J")
    }
}
