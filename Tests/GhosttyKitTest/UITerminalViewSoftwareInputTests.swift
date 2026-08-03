#if canImport(UIKit)
    import Foundation
    import GhosttyKit
    @testable import GhosttyTerminal
    import Testing
    import UIKit

    @Suite(.serialized)
    @MainActor
    struct UITerminalViewSoftwareInputTests {
        @Test
        func defaultsEnableKeyboardAndAccessory() {
            let view = UITerminalView()

            #expect(view.softwareInputDelegate == nil)
            #expect(view.hardwareInputDelegate == nil)
            #expect(view.isKeyboardInputEnabled)
            #expect(view.canBecomeFirstResponder)
            #expect(view.showsInputAccessory)
            #if !targetEnvironment(macCatalyst)
                #expect(view.inputAccessoryView != nil)
            #endif
        }

        @Test
        func softwareInputDelegateIsWeak() {
            let view = UITerminalView()
            var delegate: SoftwareInputDelegateSpy? = .init()

            view.softwareInputDelegate = delegate
            #expect(view.softwareInputDelegate != nil)

            delegate = nil
            #expect(view.softwareInputDelegate == nil)
        }

        @Test
        func hardwareInputDelegateIsWeak() {
            let view = UITerminalView()
            var delegate: HardwareInputDelegateSpy? = .init()

            view.hardwareInputDelegate = delegate
            #expect(view.hardwareInputDelegate != nil)

            delegate = nil
            #expect(view.hardwareInputDelegate == nil)
        }

        @Test
        func handledHardwarePressBypassesGhosttyAndSuppressesTextCallback() throws {
            let fixture = try SurfaceFixture()
            let hardwareDelegate = HardwareInputDelegateSpy()
            hardwareDelegate.result = true
            let softwareDelegate = SoftwareInputDelegateSpy()
            softwareDelegate.insertResult = true
            fixture.view.hardwareInputDelegate = hardwareDelegate
            fixture.view.softwareInputDelegate = softwareDelegate
            let identity = ObjectIdentifier(NSObject())

            let handled = fixture.view.handleHardwarePressBegan(
                .init(
                    usage: UInt16(UIKeyboardHIDUsage.keyboardD.rawValue),
                    characters: "d",
                    charactersIgnoringModifiers: "d",
                    modifierFlags: .command
                ),
                identity: identity
            )
            fixture.view.insertText("d")

            #expect(handled)
            #expect(hardwareDelegate.events.count == 1)
            #expect(hardwareDelegate.events.first?.charactersIgnoringModifiers == "d")
            #expect(hardwareDelegate.events.first?.modifierFlags == .command)
            #expect(softwareDelegate.insertedTexts.isEmpty)
            #expect(fixture.output.data.isEmpty)
            #expect(fixture.view.hardwarePressesHandledByDelegate.contains(identity))
        }

        @Test
        func rejectedHardwarePressFallsThroughToGhostty() async throws {
            let fixture = try SurfaceFixture()
            let delegate = HardwareInputDelegateSpy()
            delegate.result = false
            fixture.view.hardwareInputDelegate = delegate

            let handled = fixture.view.handleHardwarePressBegan(
                .init(
                    usage: UInt16(UIKeyboardHIDUsage.keyboardA.rawValue),
                    characters: "a",
                    charactersIgnoringModifiers: "a",
                    modifierFlags: []
                ),
                identity: ObjectIdentifier(NSObject())
            )
            fixture.controller.tick()
            await fixture.output.waitForData()

            #expect(!handled)
            #expect(delegate.events.count == 1)
            #expect(fixture.output.data == Data("a".utf8))
        }

        @Test
        func insertTextStopsAfterDelegateHandlesIt() {
            let view = UITerminalView()
            let delegate = SoftwareInputDelegateSpy()
            delegate.insertResult = true
            view.softwareInputDelegate = delegate

            view.insertText("hello")

            #expect(delegate.insertedTexts == ["hello"])
        }

        @Test
        func directAndReplacementTextUseDelegateOnce() throws {
            let fixture = try SurfaceFixture()
            let delegate = SoftwareInputDelegateSpy()
            delegate.insertResult = true
            fixture.view.softwareInputDelegate = delegate

            fixture.view.insertText("direct")
            fixture.view.replace(
                TerminalTextRange(location: 0, length: 0),
                withText: "replacement"
            )

            #expect(delegate.insertedTexts == ["direct", "replacement"])
            #expect(fixture.output.data.isEmpty)
        }

        @Test
        func falseDelegateResultFallsBackToSurface() throws {
            let fixture = try SurfaceFixture()
            let delegate = SoftwareInputDelegateSpy()
            delegate.insertResult = false
            fixture.view.softwareInputDelegate = delegate

            fixture.view.insertText("fallback")

            #expect(delegate.insertedTexts == ["fallback"])
            #expect(fixture.output.data == Data("fallback".utf8))
        }

        @Test
        func missingDelegateFallsBackToSurface() throws {
            let fixture = try SurfaceFixture()

            fixture.view.insertText("surface")

            #expect(fixture.output.data == Data("surface".utf8))
        }

        @Test
        func unmarkCommitUsesDelegateAndPreservesInputNotifications() throws {
            let fixture = try SurfaceFixture()
            let softwareDelegate = SoftwareInputDelegateSpy()
            softwareDelegate.insertResult = true
            let textDelegate = TextInputDelegateSpy()
            fixture.view.softwareInputDelegate = softwareDelegate
            fixture.view.inputDelegate = textDelegate

            fixture.view.setMarkedText(
                "compose",
                selectedRange: NSRange(location: 7, length: 0)
            )
            textDelegate.events.removeAll()
            fixture.view.unmarkText()

            #expect(softwareDelegate.insertedTexts == ["compose"])
            #expect(fixture.output.data.isEmpty)
            #expect(fixture.view.markedTextRange == nil)
            #expect(textDelegate.events == [
                "textWillChange",
                "selectionWillChange",
                "selectionDidChange",
                "textDidChange",
            ])
        }

        @Test
        func insertTextCommitClearsMarkedTextAndUsesDelegate() throws {
            let fixture = try SurfaceFixture()
            let delegate = SoftwareInputDelegateSpy()
            delegate.insertResult = true
            fixture.view.softwareInputDelegate = delegate
            fixture.view.setMarkedText(
                "preedit",
                selectedRange: NSRange(location: 7, length: 0)
            )

            fixture.view.insertText("final")

            #expect(delegate.insertedTexts == ["final"])
            #expect(fixture.output.data.isEmpty)
            #expect(fixture.view.markedTextRange == nil)
        }

        @Test
        func markedTextDeletionPrecedesHardwareSuppressionAndDelegate() {
            let view = UITerminalView()
            let delegate = SoftwareInputDelegateSpy()
            delegate.deleteResult = true
            view.softwareInputDelegate = delegate
            view.setMarkedText("x", selectedRange: NSRange(location: 1, length: 0))
            view.hardwareKeyHandled = true

            view.deleteBackward()

            #expect(view.markedTextRange == nil)
            #expect(!view.hardwareKeyHandled)
            #expect(delegate.deleteCallCount == 0)
        }

        @Test
        func printableHardwareKeySuppressesDuplicateSoftwareCallback() async throws {
            let fixture = try SurfaceFixture()
            let delegate = SoftwareInputDelegateSpy()
            delegate.insertResult = true
            fixture.view.softwareInputDelegate = delegate

            fixture.view.handleKeyPress(
                .init(
                    usage: UInt16(UIKeyboardHIDUsage.keyboardA.rawValue),
                    characters: "a",
                    charactersIgnoringModifiers: "a",
                    modifierFlags: []
                ),
                action: GHOSTTY_ACTION_PRESS
            )
            fixture.controller.tick()
            fixture.view.insertText("a")
            await fixture.output.waitForData()

            #expect(delegate.insertedTexts.isEmpty)
            #expect(fixture.output.data == Data("a".utf8))
            #expect(!fixture.view.hardwareKeyHandled)
        }

        @Test
        func backspaceHardwareKeySuppressesDuplicateSoftwareCallback() async throws {
            let fixture = try SurfaceFixture()
            let delegate = SoftwareInputDelegateSpy()
            delegate.deleteResult = true
            fixture.view.softwareInputDelegate = delegate

            fixture.view.handleKeyPress(
                .init(
                    usage: UInt16(UIKeyboardHIDUsage.keyboardDeleteOrBackspace.rawValue),
                    characters: "",
                    charactersIgnoringModifiers: "",
                    modifierFlags: []
                ),
                action: GHOSTTY_ACTION_PRESS
            )
            fixture.controller.tick()
            fixture.view.deleteBackward()
            await fixture.output.waitForData()

            #expect(delegate.deleteCallCount == 0)
            #expect(fixture.output.data == Data([0x7F]))
            #expect(!fixture.view.hardwareKeyHandled)
        }

        @Test
        func modifiedPrintableSequenceOnlyChangesCommittedTextSink() async throws {
            try await expectCommittedTextSinkIsOnlyDifference(
                event: .init(
                    usage: UInt16(UIKeyboardHIDUsage.keyboardA.rawValue),
                    characters: "å",
                    charactersIgnoringModifiers: "a",
                    modifierFlags: .alternate
                ),
                committedText: "å"
            )
        }

        @Test
        func deadKeySequenceOnlyChangesCommittedTextSink() async throws {
            try await expectCommittedTextSinkIsOnlyDifference(
                event: .init(
                    usage: UInt16(UIKeyboardHIDUsage.keyboardE.rawValue),
                    characters: "",
                    charactersIgnoringModifiers: "e",
                    modifierFlags: .alternate
                ),
                committedText: "é"
            )
        }

        #if !targetEnvironment(macCatalyst)
            @Test
            func stickyModifierFallbackUsesSoftwareDelegate() {
                let view = UITerminalView()
                let delegate = SoftwareInputDelegateSpy()
                delegate.insertResult = true
                view.softwareInputDelegate = delegate
                view.stickyModifiers.toggle(.ctrl)

                view.inputHandler.insertText("🙂", applyingStickyModifiers: true)

                #expect(delegate.insertedTexts == ["🙂"])
            }
        #endif

        @Test
        func deleteDelegateHandlesOrFallsBack() throws {
            let fixture = try SurfaceFixture()
            let delegate = SoftwareInputDelegateSpy()
            fixture.view.softwareInputDelegate = delegate

            delegate.deleteResult = true
            fixture.view.deleteBackward()
            #expect(delegate.deleteCallCount == 1)
            #expect(fixture.output.data.isEmpty)

            delegate.deleteResult = false
            fixture.view.deleteBackward()
            #expect(delegate.deleteCallCount == 2)
            #expect(fixture.output.data == Data([0x7F]))
        }

        @Test
        func disablingKeyboardResignsActiveResponder() throws {
            let fixture = try SurfaceFixture()
            #expect(fixture.view.becomeFirstResponder())
            #expect(fixture.view.isFirstResponder)

            fixture.view.isKeyboardInputEnabled = false

            #expect(!fixture.view.canBecomeFirstResponder)
            #expect(!fixture.view.isFirstResponder)
        }

        @Test
        func disabledKeyboardDoesNotFocusSurfaceWhenResponderAttemptFails() throws {
            let fixture = try SurfaceFixture()
            let delegate = FocusDelegateSpy()
            fixture.view.delegate = delegate
            fixture.view.isKeyboardInputEnabled = false

            let becameFirstResponder = fixture.view.becomeFirstResponder()

            #expect(!becameFirstResponder)
            #expect(!fixture.view.isFirstResponder)
            #expect(delegate.focusChanges.isEmpty)
        }

        @Test
        func successfulResponderAttemptFocusesSurface() throws {
            let fixture = try SurfaceFixture()
            let delegate = FocusDelegateSpy()
            fixture.view.delegate = delegate

            let becameFirstResponder = fixture.view.becomeFirstResponder()

            #expect(becameFirstResponder)
            #expect(fixture.view.isFirstResponder)
            #expect(delegate.focusChanges == [true])
        }

        @Test
        func accessoryVisibilityCanBeChanged() async throws {
            #if !targetEnvironment(macCatalyst)
                let fixture = try SurfaceFixture()
                #expect(fixture.view.becomeFirstResponder())
                #expect(fixture.view.inputAccessoryView != nil)

                fixture.view.showsInputAccessory = false
                #expect(fixture.view.inputAccessoryView == nil)

                let delegate = SoftwareInputDelegateSpy()
                delegate.insertResult = true
                fixture.view.softwareInputDelegate = delegate
                fixture.view.handleKeyPress(
                    .init(
                        usage: UInt16(UIKeyboardHIDUsage.keyboardA.rawValue),
                        characters: "a",
                        charactersIgnoringModifiers: "a",
                        modifierFlags: []
                    ),
                    action: GHOSTTY_ACTION_PRESS
                )
                fixture.controller.tick()
                fixture.view.insertText("a")
                await fixture.output.waitForData()
                #expect(fixture.output.data == Data("a".utf8))
                #expect(delegate.insertedTexts.isEmpty)

                fixture.view.showsInputAccessory = true
                #expect(fixture.view.inputAccessoryView != nil)
            #else
                let view = UITerminalView()
                view.showsInputAccessory = false
                #expect(!view.showsInputAccessory)
            #endif
        }

        private func expectCommittedTextSinkIsOnlyDifference(
            event: TerminalUIKitKeyEvent,
            committedText: String
        ) async throws {
            let fallbackFixture = try SurfaceFixture()
            fallbackFixture.view.handleKeyPress(event, action: GHOSTTY_ACTION_PRESS)
            fallbackFixture.controller.tick()
            await fallbackFixture.output.waitForData()
            let fallbackPhysicalOutput = fallbackFixture.output.data
            fallbackFixture.view.insertText(committedText)

            let handledFixture = try SurfaceFixture()
            let delegate = SoftwareInputDelegateSpy()
            delegate.insertResult = true
            handledFixture.view.softwareInputDelegate = delegate
            handledFixture.view.handleKeyPress(event, action: GHOSTTY_ACTION_PRESS)
            handledFixture.controller.tick()
            await handledFixture.output.waitForData()
            let handledPhysicalOutput = handledFixture.output.data
            handledFixture.view.insertText(committedText)

            #expect(handledPhysicalOutput == fallbackPhysicalOutput)
            #expect(
                fallbackFixture.output.data
                    == fallbackPhysicalOutput + Data(committedText.utf8)
            )
            #expect(handledFixture.output.data == handledPhysicalOutput)
            #expect(delegate.insertedTexts == [committedText])
            #expect(!fallbackFixture.view.hardwareKeyHandled)
            #expect(!handledFixture.view.hardwareKeyHandled)
        }
    }

    @MainActor
    private final class SoftwareInputDelegateSpy: TerminalSoftwareInputDelegate {
        var insertedTexts: [String] = []
        var deleteCallCount = 0
        var insertResult = false
        var deleteResult = false

        func terminalView(_: UITerminalView, insertText text: String) -> Bool {
            insertedTexts.append(text)
            return insertResult
        }

        func terminalViewDeleteBackward(_: UITerminalView) -> Bool {
            deleteCallCount += 1
            return deleteResult
        }
    }

    @MainActor
    private final class HardwareInputDelegateSpy: TerminalHardwareInputDelegate {
        var events: [TerminalHardwareKeyEvent] = []
        var result = false

        func terminalView(
            _: UITerminalView,
            handleHardwareKey event: TerminalHardwareKeyEvent
        ) -> Bool {
            events.append(event)
            return result
        }
    }

    @MainActor
    private final class FocusDelegateSpy: TerminalSurfaceFocusDelegate {
        var focusChanges: [Bool] = []

        func terminalDidChangeFocus(_ focused: Bool) {
            focusChanges.append(focused)
        }
    }

    @MainActor
    private final class TextInputDelegateSpy: NSObject, UITextInputDelegate {
        var events: [String] = []

        func selectionWillChange(_: (any UITextInput)?) {
            events.append("selectionWillChange")
        }

        func selectionDidChange(_: (any UITextInput)?) {
            events.append("selectionDidChange")
        }

        func textWillChange(_: (any UITextInput)?) {
            events.append("textWillChange")
        }

        func textDidChange(_: (any UITextInput)?) {
            events.append("textDidChange")
        }

        @available(iOS 18.4, *)
        func conversationContext(
            _: UIConversationContext?,
            didChange _: (any UITextInput)?
        ) {}
    }

    private final class OutputRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var storage = Data()

        var data: Data {
            lock.withLock { storage }
        }

        func append(_ data: Data) {
            lock.withLock { storage.append(data) }
        }

        func waitForData() async {
            for _ in 0 ..< 100 where data.isEmpty {
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
        }
    }

    @MainActor
    private final class SurfaceFixture {
        let output = OutputRecorder()
        let view = UITerminalView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let viewController = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let controller = TerminalController()

        init() throws {
            let output = output
            let session = InMemoryTerminalSession(
                write: { output.append($0) },
                resize: { _ in }
            )
            view.configuration = .init(backend: .inMemory(session))
            viewController.view = view
            window.rootViewController = viewController
            window.makeKeyAndVisible()
            view.controller = controller
            guard view.surface != nil else {
                throw SurfaceFixtureError.creationFailed
            }
        }
    }

    private enum SurfaceFixtureError: Error {
        case creationFailed
    }
#endif
