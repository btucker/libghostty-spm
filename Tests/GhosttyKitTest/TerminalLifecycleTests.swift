@testable import GhosttyTerminal
import Testing
#if canImport(UIKit)
    import QuartzCore
    import UIKit
#endif

@MainActor
struct TerminalLifecycleTests {
    @Test
    func `failed surface creation does not retain bridge`() {
        let controller = TerminalController()
        let bridge = TerminalCallbackBridge()

        let surface = controller.createSurface(
            bridge: bridge,
            configuration: .init()
        ) { _ in }

        #expect(surface == nil)
        #expect(controller.retainedBridgeCount == 0)
    }

    @Test
    func `switching controllers removes bridge from old controller`() {
        let oldController = TerminalController()
        let newController = TerminalController()
        let coordinator = TerminalSurfaceCoordinator()

        coordinator.isAttached = { false }
        oldController.retain(coordinator.bridge)
        #expect(oldController.retainedBridgeCount == 1)

        coordinator.controller = oldController
        #expect(oldController.retainedBridgeCount == 0)

        oldController.retain(coordinator.bridge)
        #expect(oldController.retainedBridgeCount == 1)

        coordinator.controller = newController

        #expect(oldController.retainedBridgeCount == 0)
        #expect(newController.retainedBridgeCount == 0)
    }

    @Test
    func `free surface removes retained bridge`() {
        let controller = TerminalController()
        let coordinator = TerminalSurfaceCoordinator()

        coordinator.isAttached = { false }
        coordinator.controller = controller

        controller.retain(coordinator.bridge)
        #expect(controller.retainedBridgeCount == 1)

        coordinator.freeSurface()

        #expect(controller.retainedBridgeCount == 0)
    }

    @Test
    func `suspended wakeup does not schedule render`() {
        let controller = TerminalController()
        var wakeups = 0

        controller.shouldProcessWakeup = { false }
        controller.onWakeup = {
            wakeups += 1
        }

        controller.handleWakeup()

        #expect(wakeups == 0)
    }

    @Test
    func `application active state controls immediate ticks`() async {
        let coordinator = TerminalSurfaceCoordinator()
        var renders = 0

        coordinator.isAttached = { true }
        coordinator.onPostRender = {
            renders += 1
        }

        coordinator.setApplicationActive(false)
        coordinator.requestImmediateTick()
        await Task.yield()

        #expect(renders == 0)

        coordinator.setApplicationActive(true)
        await Task.yield()

        #expect(renders == 1)
    }

    #if canImport(UIKit)
        @Test
        func `temporary UIKit detachment preserves the surface until reattachment`() throws {
            let (window, viewController, terminalView, _) = try makeUIKitTerminal()

            let originalSurface = try #require(terminalView.surface)

            terminalView.removeFromSuperview()

            #expect(terminalView.window == nil)
            #expect(terminalView.surface === originalSurface)

            viewController.view.addSubview(terminalView)

            #expect(terminalView.window === window)
            #expect(terminalView.surface === originalSurface)
        }

        @Test
        func `detached configuration change waits to rebuild until reattachment`() throws {
            let (window, viewController, terminalView, _) = try makeUIKitTerminal()
            let originalSurface = try #require(terminalView.surface)

            terminalView.removeFromSuperview()
            var changedConfiguration = terminalView.configuration
            changedConfiguration.fontSize = 18
            terminalView.configuration = changedConfiguration

            #expect(terminalView.surface === originalSurface)

            viewController.view.addSubview(terminalView)

            #expect(terminalView.window === window)
            #expect(terminalView.surface !== originalSurface)
        }

        @Test
        func `detached controller change keeps old bridge until reattachment`() throws {
            let (window, viewController, terminalView, oldController) = try makeUIKitTerminal()
            let originalSurface = try #require(terminalView.surface)
            let newController = TerminalController()

            #expect(oldController.retainedBridgeCount == 1)
            terminalView.removeFromSuperview()
            terminalView.controller = newController

            #expect(terminalView.surface === originalSurface)
            #expect(oldController.retainedBridgeCount == 1)
            #expect(newController.retainedBridgeCount == 0)

            viewController.view.addSubview(terminalView)

            #expect(terminalView.window === window)
            #expect(terminalView.surface !== originalSurface)
            #expect(oldController.retainedBridgeCount == 0)
            #expect(newController.retainedBridgeCount == 1)
        }

        @Test
        func `surface rebuild clears the session that owned the old surface`() throws {
            let (_, _, terminalView, _) = try makeUIKitTerminal()
            let oldSession = try #require(terminalView.configuration.inMemorySession)
            let newSession = InMemoryTerminalSession(write: { _ in }, resize: { _ in })

            #expect(oldSession.currentSurface != nil)
            terminalView.configuration = .init(backend: .inMemory(newSession))

            #expect(oldSession.currentSurface == nil)
            #expect(newSession.currentSurface == terminalView.surface?.rawValue)
        }

        @Test
        func `metrics change supersedes a reduced pace delayed tick`() throws {
            let (window, _, terminalView, _) = try makeUIKitTerminal()
            var renders = 0
            terminalView.core.onPostRender = { renders += 1 }
            let timestamp = ProcessInfo.processInfo.systemUptime
            terminalView.core.tick(
                context: .init(
                    duration: 0,
                    timestamp: timestamp,
                    targetTimestamp: timestamp
                )
            )
            #expect(renders == 1)

            terminalView.renderPace = .reduced(interval: 5)
            let delayedGeneration = terminalView.core.testHooks_scheduledTickGeneration
            #expect(terminalView.core.testHooks_tickScheduled)

            terminalView.bounds.size.width += 100
            terminalView.core.fitToSize()

            #expect(terminalView.window === window)
            #expect(terminalView.core.testHooks_tickScheduled)
            #expect(terminalView.core.testHooks_scheduledTickGeneration > delayedGeneration)
        }

        @Test
        func `transaction retention preserves an existing completion`() async {
            let coordinator = TerminalSurfaceCoordinator()
            var embedderCompletionCount = 0

            CATransaction.begin()
            CATransaction.setCompletionBlock {
                embedderCompletionCount += 1
            }
            coordinator.retainThroughCurrentTransaction()

            #expect(embedderCompletionCount == 0)

            CATransaction.commit()
            CATransaction.flush()
            for _ in 0 ..< 100 where embedderCompletionCount == 0 {
                await Task.yield()
            }

            #expect(embedderCompletionCount == 1)
        }

        @Test
        func `final UIKit teardown survives completion replacement until commit`() async throws {
            weak var retainedView: UITerminalView?
            weak var retainedCoordinator: TerminalSurfaceCoordinator?
            var embedderCompletionCount = 0

            CATransaction.begin()
            do {
                let (_, _, terminalView, _) = try makeUIKitTerminal()
                retainedView = terminalView
                retainedCoordinator = terminalView.core
                terminalView.removeFromSuperview()
            }

            #expect(retainedCoordinator != nil)
            CATransaction.setCompletionBlock {
                embedderCompletionCount += 1
            }
            #expect(retainedCoordinator != nil)

            CATransaction.commit()
            CATransaction.flush()
            for _ in 0 ..< 100 where retainedCoordinator != nil {
                await Task.yield()
            }

            #expect(embedderCompletionCount == 1)
            #expect(retainedView == nil)
            #expect(retainedCoordinator == nil)
        }

        private func makeUIKitTerminal() throws -> (
            window: UIWindow,
            viewController: UIViewController,
            terminalView: UITerminalView,
            controller: TerminalController
        ) {
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
            let viewController = UIViewController()
            let terminalView = UITerminalView(
                frame: CGRect(x: 0, y: 0, width: 800, height: 600)
            )
            let session = InMemoryTerminalSession(write: { _ in }, resize: { _ in })
            let controller = TerminalController()

            window.rootViewController = viewController
            window.makeKeyAndVisible()
            viewController.view.addSubview(terminalView)
            terminalView.configuration = .init(backend: .inMemory(session))
            terminalView.controller = controller
            _ = try #require(terminalView.surface)

            return (window, viewController, terminalView, controller)
        }
    #endif
}
