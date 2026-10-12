@testable import GhosttyTerminal
import Foundation
import GhosttyKit
import Testing
#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

@MainActor
struct InMemoryTerminalTeardownTests {
    @Test("Teardown drains a blocked writer before freeing and invalidates queued output")
    func teardownMakesMailboxProgress() {
        let writerStarted = DispatchSemaphore(value: 0)
        let mailboxSpace = DispatchSemaphore(value: 0)
        let events = LockedValues<String>()
        let session = InMemoryTerminalSession(
            write: { _ in }, resize: { _ in },
            surfaceWrite: { _, data in
                events.append(String(decoding: data, as: UTF8.self))
                writerStarted.signal()
                // A bounded native mailbox needs repeated main-thread drains.
                for _ in 0..<128 { mailboxSpace.wait() }
                events.append("writer finished")
            }, processExit: { _, _, _ in events.append("stale exit") }
        )
        let surface = UnsafeMutableRawPointer(bitPattern: 1)!
        session.setSurface(surface)
        session.receive("active")
        #expect(writerStarted.wait(timeout: .now() + 1) == .success)
        session.receive("stale")
        session.finish(exitCode: 0, runtimeMilliseconds: 0)

        // Rescue the old blocking implementation so RED reports a failure
        // rather than leaving the test process deadlocked forever.
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            events.append("watchdog rescue")
            for _ in 0..<128 { mailboxSpace.signal() }
        }
        let start = ProcessInfo.processInfo.systemUptime
        session.clearSurface(ifMatches: surface, whileWaiting: {
            #expect(session.currentSurface == nil)
            mailboxSpace.signal()
        })
        events.append("free")
        #expect(ProcessInfo.processInfo.systemUptime - start < 0.5)
        session.waitForPendingOutput()
        #expect(events.values == ["active", "writer finished", "free"])
        #expect(session.currentSurface == nil)
    }

    @Test
    func replacementCancelsTheRestOfALargePacket() {
        let started = DispatchSemaphore(value: 0)
        let space = DispatchSemaphore(value: 0)
        let events = LockedValues<String>()
        let access = InMemoryTerminalSurfaceAccess(write: { surface, data in
            events.append("\(Int(bitPattern: surface)):\(data.count)")
            if Int(bitPattern: surface) == 1 {
                started.signal()
                space.wait()
            }
        }, processExit: { _, _, _ in events.append("exit") })
        let old = UnsafeMutableRawPointer(bitPattern: 1)!
        let new = UnsafeMutableRawPointer(bitPattern: 2)!
        access.setSurface(old)
        access.enqueueWrite(Data(repeating: 65, count: 100_000))
        #expect(started.wait(timeout: .now() + 1) == .success)
        access.enqueueProcessExit(exitCode: 0, runtimeMilliseconds: 0)
        access.setSurface(new, whileWaiting: { space.signal() })
        #expect(!access.clearSurface(ifMatches: old))
        #expect(access.currentSurface == new)
        access.enqueueWrite(Data("new".utf8))
        access.enqueueProcessExit(exitCode: 0, runtimeMilliseconds: 0)
        access.waitForPendingOutput()
        #expect(events.values == ["1:4096", "2:3", "exit"])
    }

    @Test
    func chunksPreserveBytesAndExitOrdering() {
        let events = LockedValues<String>()
        let access = InMemoryTerminalSurfaceAccess(write: { _, data in
            events.append(data.base64EncodedString())
        }, processExit: { _, _, _ in events.append("exit") })
        access.setSurface(UnsafeMutableRawPointer(bitPattern: 3)!)
        let text = String(repeating: "a", count: 4095) + "é-tail"
        access.enqueueWrite(Data(text.utf8))
        access.enqueueWrite(Data("next".utf8))
        access.enqueueProcessExit(exitCode: 0, runtimeMilliseconds: 0)
        access.waitForPendingOutput()
        // Decode only after concatenating bytes: chunk boundaries can split UTF-8.
        let chunks = events.values.dropLast().compactMap { Data(base64Encoded: $0) }
        #expect(chunks.map(\.count) == [4096, 6, 4])
        #expect(chunks.reduce(into: Data()) { $0.append($1) } == Data((text + "next").utf8))
        #expect(events.values.last == "exit")
    }

    @Test
    func staleOwnerStillWaitsForItsWriterDuringReplacement() {
        let started = DispatchSemaphore(value: 0)
        let space = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        let access = InMemoryTerminalSurfaceAccess(write: { _, _ in
            started.signal()
            space.wait()
            finished.signal()
        }, processExit: { _, _, _ in })
        let old = UnsafeMutableRawPointer(bitPattern: 4)!
        let new = UnsafeMutableRawPointer(bitPattern: 5)!
        access.setSurface(old)
        access.enqueueWrite(Data("active".utf8))
        #expect(started.wait(timeout: .now() + 1) == .success)
        var clearedOldOwner = false
        access.setSurface(new, whileWaiting: {
            if !clearedOldOwner {
                clearedOldOwner = true
                // Native pumping can reenter an old owner's teardown after
                // replacement has made the current pointer nil.
                #expect(!access.clearSurface(ifMatches: old, whileWaiting: { space.signal() }))
                #expect(finished.wait(timeout: .now()) == .success)
            }
            space.signal()
        })
        #expect(access.currentSurface == new)
        access.waitForPendingOutput()
    }

    @Test
    func replacementDrainsTheOldMailboxAndClearDrainsTheNewMailbox() {
        let started = DispatchSemaphore(value: 0)
        let space = DispatchSemaphore(value: 0)
        let access = InMemoryTerminalSurfaceAccess(write: { _, _ in
            started.signal()
            space.wait()
        }, processExit: { _, _, _ in })
        var oldDrains = 0
        var newDrains = 0
        let old = UnsafeMutableRawPointer(bitPattern: 6)!
        let new = UnsafeMutableRawPointer(bitPattern: 7)!
        access.setSurface(old, processMailbox: {
            oldDrains += 1
            if oldDrains == 1 { space.signal() }
        })
        access.enqueueWrite(Data("old".utf8))
        #expect(started.wait(timeout: .now() + 1) == .success)
        access.setSurface(new, processMailbox: {
            newDrains += 1
            if newDrains == 1 { space.signal() }
        })
        #expect(oldDrains > 0)
        #expect(newDrains == 0)
        access.enqueueWrite(Data("new".utf8))
        #expect(started.wait(timeout: .now() + 1) == .success)
        #expect(!access.clearSurface(ifMatches: old))
        #expect(access.currentSurface == new)
        #expect(access.clearSurface(ifMatches: new))
        #expect(newDrains > 0)
        access.waitForPendingOutput()
    }

    @Test
    func newerReplacementWinsWhileAnOlderReplacementWaits() {
        let started = DispatchSemaphore(value: 0)
        let space = DispatchSemaphore(value: 0)
        let access = InMemoryTerminalSurfaceAccess(write: { _, _ in
            started.signal()
            space.wait()
        }, processExit: { _, _, _ in })
        let old = UnsafeMutableRawPointer(bitPattern: 8)!
        let replaced = UnsafeMutableRawPointer(bitPattern: 9)!
        let newest = UnsafeMutableRawPointer(bitPattern: 10)!
        access.setSurface(old)
        access.enqueueWrite(Data("old".utf8))
        #expect(started.wait(timeout: .now() + 1) == .success)
        var replacedAgain = false
        access.setSurface(replaced, whileWaiting: {
            if !replacedAgain {
                replacedAgain = true
                // An empty owner's clear must not invalidate a replacement.
                #expect(access.clearSurface(ifMatches: nil))
                access.setSurface(newest)
            }
            space.signal()
        })
        #expect(access.currentSurface == newest)
        #expect(!access.clearSurface(ifMatches: old))
        #expect(access.currentSurface == newest)
        access.waitForPendingOutput()
    }
}
