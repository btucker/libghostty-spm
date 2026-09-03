import CoreGraphics
import Testing
@testable import GhosttyTerminal

@Suite
struct TerminalTouchScrollConfigurationTests {
    @Test
    func constrainedConnectionPolicyReducesRemoteInputPressure() {
        let configuration = TerminalTouchScrollConfiguration.constrainedConnection

        #expect(configuration.multiplier == 1)
        #expect(configuration.maximumEventRate == 30)
        #expect(!configuration.momentumEnabled)
        #expect(configuration.minimumSendInterval == 1.0 / 30.0)
    }

    @Test
    func rateLimiterCoalescesMovementUntilIntervalElapses() {
        var limiter = TerminalScrollRateLimiter()
        limiter.begin(at: 10)

        #expect(limiter.append(
            CGPoint(x: 2, y: 3),
            at: 10.01,
            minimumInterval: 1.0 / 30.0
        ) == nil)
        #expect(limiter.append(
            CGPoint(x: 4, y: 5),
            at: 10.02,
            minimumInterval: 1.0 / 30.0
        ) == nil)

        let dispatched = limiter.append(
            CGPoint(x: 6, y: 7),
            at: 10.04,
            minimumInterval: 1.0 / 30.0
        )

        #expect(dispatched == CGPoint(x: 12, y: 15))
        #expect(limiter.flush() == nil)
    }

    @Test
    func rateLimiterFlushesTrailingMovement() {
        var limiter = TerminalScrollRateLimiter()
        limiter.begin(at: 20)
        _ = limiter.append(
            CGPoint(x: 3, y: -4),
            at: 20.01,
            minimumInterval: 1.0 / 30.0
        )

        #expect(limiter.flush() == CGPoint(x: 3, y: -4))
        #expect(limiter.flush() == nil)
    }

    @Test
    func unrestrictedPolicyDispatchesEveryMovement() {
        var limiter = TerminalScrollRateLimiter()
        limiter.begin(at: 30)

        let dispatched = limiter.append(
            CGPoint(x: 1, y: 2),
            at: 30,
            minimumInterval: 0
        )

        #expect(dispatched == CGPoint(x: 1, y: 2))
    }
}
