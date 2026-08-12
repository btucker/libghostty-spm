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
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
            let viewController = UIViewController()
            let terminalView = UITerminalView(
                frame: CGRect(x: 0, y: 0, width: 800, height: 600)
            )
            let session = InMemoryTerminalSession(write: { _ in }, resize: { _ in })

            window.rootViewController = viewController
            window.makeKeyAndVisible()
            viewController.view.addSubview(terminalView)
            terminalView.configuration = .init(backend: .inMemory(session))
            terminalView.controller = TerminalController()

            let originalSurface = try #require(terminalView.surface)

            terminalView.removeFromSuperview()

            #expect(terminalView.window == nil)
            #expect(terminalView.surface === originalSurface)

            viewController.view.addSubview(terminalView)

            #expect(terminalView.window === window)
            #expect(terminalView.surface === originalSurface)
        }

        @Test
        func `final UIKit teardown waits for the detaching transaction`() async {
            weak var retainedCoordinator: TerminalSurfaceCoordinator?

            CATransaction.begin()
            do {
                let coordinator = TerminalSurfaceCoordinator()
                retainedCoordinator = coordinator
                coordinator.retainThroughCurrentTransaction()
            }

            #expect(retainedCoordinator != nil)

            CATransaction.commit()
            CATransaction.flush()
            for _ in 0 ..< 100 where retainedCoordinator != nil {
                await Task.yield()
            }

            #expect(retainedCoordinator == nil)
        }
    #endif
}
