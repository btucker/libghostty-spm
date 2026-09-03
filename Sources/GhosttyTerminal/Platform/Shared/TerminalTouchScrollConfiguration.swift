import CoreGraphics
import Foundation

/// Controls how direct-touch scrolling is translated into libghostty scroll
/// input. `UITerminalView` uses `standard` unless a host supplies a separate
/// policy for terminals that have captured the mouse.
public struct TerminalTouchScrollConfiguration: Equatable, Sendable {
    public let multiplier: Double
    public let maximumEventRate: Double?
    public let momentumEnabled: Bool

    public init(
        multiplier: Double = 3,
        maximumEventRate: Double? = nil,
        momentumEnabled: Bool = true
    ) {
        self.multiplier = multiplier.isFinite ? max(0, multiplier) : 0
        if let maximumEventRate,
           maximumEventRate.isFinite,
           maximumEventRate > 0
        {
            self.maximumEventRate = maximumEventRate
        } else {
            self.maximumEventRate = nil
        }
        self.momentumEnabled = momentumEnabled
    }

    public static let standard = TerminalTouchScrollConfiguration()

    /// Reduces the event and momentum backlog produced by a remote
    /// mouse-reporting terminal while keeping direct finger tracking.
    public static let constrainedConnection = TerminalTouchScrollConfiguration(
        multiplier: 1,
        maximumEventRate: 30,
        momentumEnabled: false
    )

    var minimumSendInterval: TimeInterval {
        maximumEventRate.map { 1 / $0 } ?? 0
    }
}

struct TerminalScrollRateLimiter {
    private var pending = CGPoint.zero
    private var lastDispatchTime: TimeInterval?

    mutating func begin(at time: TimeInterval) {
        pending = .zero
        lastDispatchTime = time
    }

    mutating func append(
        _ delta: CGPoint,
        at time: TimeInterval,
        minimumInterval: TimeInterval
    ) -> CGPoint? {
        pending.x += delta.x
        pending.y += delta.y

        if minimumInterval > 0,
           let lastDispatchTime,
           time - lastDispatchTime < minimumInterval
        {
            return nil
        }

        self.lastDispatchTime = time
        return flush()
    }

    mutating func flush() -> CGPoint? {
        guard pending != .zero else { return nil }
        let result = pending
        pending = .zero
        return result
    }

    mutating func reset() {
        pending = .zero
        lastDispatchTime = nil
    }
}
