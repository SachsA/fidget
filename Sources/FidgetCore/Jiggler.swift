import Foundation
import CoreGraphics
import ApplicationServices
import IOKit.pwr_mgt

public enum EngineState: Equatable {
    case disabled
    case outsideSchedule
    case missingPermission
    case active
}

/// The engine: checks user inactivity every couple of seconds and nudges the mouse when needed.
@MainActor
public final class Jiggler {
    public private(set) var settings: Settings
    public private(set) var state: EngineState = .disabled
    public private(set) var lastJiggle: Date?

    public var onStateChange: ((EngineState) -> Void)?
    public var onJiggle: ((Date) -> Void)?

    private var timer: Timer?
    private let sleepGuard = PowerAssertion()
    private var activityID: IOPMAssertionID = 0

    public init(settings: Settings) {
        self.settings = settings.clamped()
    }

    public func update(settings: Settings) {
        self.settings = settings.clamped()
        tick()
    }

    public func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        tick()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        sleepGuard.set(false)
        setState(.disabled)
    }

    public func tick(now: Date = Date()) {
        let inSchedule = settings.schedule.isActive(at: now)
        sleepGuard.set(settings.enabled && inSchedule && settings.preventSleep)

        guard settings.enabled else { return setState(.disabled) }
        guard inSchedule else { return setState(.outsideSchedule) }
        guard Accessibility.isTrusted else { return setState(.missingPermission) }
        setState(.active)

        let idle = SystemIdle.seconds()
        let sinceLast = lastJiggle.map { now.timeIntervalSince($0) } ?? .infinity
        if idle >= settings.idleInterval && sinceLast >= settings.idleInterval {
            jiggle()
            lastJiggle = now
            onJiggle?(now)
        }
    }

    /// Nudges the mouse right now, whatever the idle time.
    public func jiggle() {
        Mouse.nudge(distance: settings.distance, mode: settings.mode)
        if settings.mode == .zen {
            // Also tells the power manager the user is active, which resets the idle timer
            // without any visible movement.
            IOPMAssertionDeclareUserActivity("Fidget" as CFString, kIOPMUserActiveLocal, &activityID)
        }
    }

    private func setState(_ new: EngineState) {
        guard new != state else { return }
        state = new
        onStateChange?(new)
    }
}

enum SystemIdle {
    private static let anyInput = CGEventType(rawValue: ~0)!

    static func seconds() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInput)
    }
}

enum Mouse {
    static func nudge(distance: Int, mode: JiggleMode) {
        guard let position = CGEvent(source: nil)?.location else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        let points: [CGPoint]
        switch mode {
        case .visible:
            let d = CGFloat(distance)
            points = [CGPoint(x: position.x + d, y: position.y + d), position]
        case .zen:
            points = [position]
        }
        for point in points {
            CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                    mouseCursorPosition: point, mouseButton: .left)?
                .post(tap: .cghidEventTap)
            usleep(30_000)
        }
    }
}

/// Holds a "prevent display sleep" assertion while on. Released automatically if the process dies.
final class PowerAssertion {
    private var id: IOPMAssertionID = 0
    private var held = false

    func set(_ on: Bool) {
        if on && !held {
            held = IOPMAssertionCreateWithName(
                "PreventUserIdleDisplaySleep" as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Fidget keeps the display awake" as CFString,
                &id) == kIOReturnSuccess
        } else if !on && held {
            IOPMAssertionRelease(id)
            held = false
        }
    }

    deinit {
        if held { IOPMAssertionRelease(id) }
    }
}

public enum Accessibility {
    public static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt asking to grant Accessibility access (only if not granted yet).
    public static func request() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    public static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
}
