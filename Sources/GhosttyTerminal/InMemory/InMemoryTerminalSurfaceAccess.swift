import Foundation
import GhosttyKit

/// Serializes host output while keeping the raw surface alive for each C call.
final class InMemoryTerminalSurfaceAccess: @unchecked Sendable {
    /// Recheck retirement between chunks, even for a very large host packet.
    static let maximumWriteSize = 4096
    typealias Write = @Sendable (ghostty_surface_t, Data) -> Void
    typealias ProcessExit = @Sendable (ghostty_surface_t, UInt32, UInt64) -> Void

    private let condition = NSCondition()
    private let outputQueue = DispatchQueue(
        label: "com.lakr233.libghostty-spm.in-memory-output",
        qos: .userInitiated
    )
    private let write: Write
    private let processExit: ProcessExit

    /// All lease state is protected by `condition`. The mailbox callback is
    /// supplied by the main-actor owner and used by main-actor lifecycle calls.
    private final class SurfaceLease {
        let rawValue: ghostty_surface_t
        let processMailbox: () -> Void
        var activeOperations = 0

        init(_ rawValue: ghostty_surface_t, processMailbox: @escaping () -> Void) {
            self.rawValue = rawValue
            self.processMailbox = processMailbox
        }
    }

    private var surface: SurfaceLease?
    private var retiringSurfaces: [ghostty_surface_t: SurfaceLease] = [:]
    /// Invalidates work that was enqueued for a surface that has been replaced.
    private var generation: UInt64 = 0

    init(
        write: @escaping Write,
        processExit: @escaping ProcessExit
    ) {
        self.write = write
        self.processExit = processExit
    }

    func setSurface(
        _ surface: ghostty_surface_t?,
        processMailbox: @escaping () -> Void = {},
        whileWaiting progress: () -> Void = {}
    ) {
        condition.lock()
        let previousSurface = self.surface
        generation &+= 1
        let replacementGeneration = generation
        self.surface = nil
        retire(previousSurface)
        waitForActiveOperations(on: previousSurface, progress: progress)
        // A later replacement may have run while the condition was unlocked.
        if generation == replacementGeneration {
            self.surface = surface.map { SurfaceLease($0, processMailbox: processMailbox) }
        }
        condition.unlock()
    }

    @discardableResult
    func clearSurface(
        ifMatches expectedSurface: ghostty_surface_t?,
        whileWaiting progress: () -> Void = {}
    ) -> Bool {
        condition.lock()
        guard let expectedSurface else {
            let alreadyClear = surface == nil
            condition.unlock()
            return alreadyClear
        }
        let matches = surface?.rawValue == expectedSurface
        let retiringSurface = matches ? surface : retiringSurfaces[expectedSurface]
        if matches {
            generation &+= 1
            surface = nil
            retire(retiringSurface)
        }
        // Replacement publishes nil before waiting. A stale owner must still
        // join its own active calls before freeing, even though it no longer
        // owns the session's current pointer.
        waitForActiveOperations(on: retiringSurface, progress: progress)
        condition.unlock()
        return matches
    }

    var currentSurface: ghostty_surface_t? {
        condition.lock()
        defer { condition.unlock() }
        return surface?.rawValue
    }

    @discardableResult
    func enqueueWrite(_ data: Data) -> Bool {
        guard let generation = currentGeneration else { return false }
        outputQueue.async { [self] in
            var offset = data.startIndex
            while offset < data.endIndex {
                let end = offset + min(Self.maximumWriteSize, data.endIndex - offset)
                guard withSurface(generation: generation, { surface in
                    let chunk = data.count <= Self.maximumWriteSize ? data : data.subdata(in: offset..<end)
                    write(surface, chunk)
                }) else { return }
                offset = end
            }
        }
        return true
    }

    @discardableResult
    func enqueueProcessExit(
        exitCode: UInt32,
        runtimeMilliseconds: UInt64
    ) -> Bool {
        guard let generation = currentGeneration else { return false }
        outputQueue.async { [self] in
            withSurface(generation: generation) { surface in
                processExit(surface, exitCode, runtimeMilliseconds)
            }
        }
        return true
    }

    func withCurrentSurface<Result>(
        _ operation: (ghostty_surface_t) -> Result
    ) -> Result? {
        condition.lock()
        guard let surface else {
            condition.unlock()
            return nil
        }
        surface.activeOperations += 1
        condition.unlock()

        defer { finishOperation(on: surface) }
        return operation(surface.rawValue)
    }

    func waitForPendingOutput() {
        outputQueue.sync {}
    }

    private var currentGeneration: UInt64? {
        condition.lock()
        defer { condition.unlock() }
        return surface == nil ? nil : generation
    }

    @discardableResult
    private func withSurface(
        generation expectedGeneration: UInt64,
        _ operation: (ghostty_surface_t) -> Void
    ) -> Bool {
        condition.lock()
        guard generation == expectedGeneration, let surface else {
            condition.unlock()
            return false
        }
        surface.activeOperations += 1
        condition.unlock()

        defer { finishOperation(on: surface) }
        operation(surface.rawValue)
        return true
    }

    private func finishOperation(on surface: SurfaceLease) {
        condition.lock()
        surface.activeOperations -= 1
        if surface.activeOperations == 0 {
            if retiringSurfaces[surface.rawValue] === surface {
                retiringSurfaces.removeValue(forKey: surface.rawValue)
            }
            condition.broadcast()
        }
        condition.unlock()
    }

    /// Called with `condition` held after removing a lease from admission.
    private func retire(_ surface: SurfaceLease?) {
        guard let surface, surface.activeOperations > 0 else { return }
        retiringSurfaces[surface.rawValue] = surface
    }

    private func waitForActiveOperations(on surface: SurfaceLease?, progress: () -> Void) {
        guard let surface else { return }
        while surface.activeOperations > 0 {
            // Output can be blocked on Ghostty's bounded app mailbox. Main
            // must drain it rather than sleep forever waiting for that output.
            // Never hold our condition across native calls or callbacks.
            condition.unlock()
            surface.processMailbox()
            progress()
            condition.lock()
            if surface.activeOperations > 0 {
                _ = condition.wait(until: Date(timeIntervalSinceNow: 0.001))
            }
        }
    }
}
