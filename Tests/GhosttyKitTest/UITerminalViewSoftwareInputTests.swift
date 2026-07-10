#if canImport(UIKit)
    import Foundation
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
        func insertTextStopsAfterDelegateHandlesIt() {
            let view = UITerminalView()
            let delegate = SoftwareInputDelegateSpy()
            delegate.insertResult = true
            view.softwareInputDelegate = delegate

            view.insertText("hello")

            #expect(delegate.insertedTexts == ["hello"])
        }

        @Test
        func directAndReplacementTextUseDelegateOnce() {
            let view = UITerminalView()
            let delegate = SoftwareInputDelegateSpy()
            delegate.insertResult = true
            view.softwareInputDelegate = delegate

            view.insertText("direct")
            view.replace(
                TerminalTextRange(location: 0, length: 0),
                withText: "replacement"
            )

            #expect(delegate.insertedTexts == ["direct", "replacement"])
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
        func unmarkCommitUsesDelegateAndPreservesInputNotifications() {
            let view = UITerminalView()
            let softwareDelegate = SoftwareInputDelegateSpy()
            softwareDelegate.insertResult = true
            let textDelegate = TextInputDelegateSpy()
            view.softwareInputDelegate = softwareDelegate
            view.inputDelegate = textDelegate

            view.setMarkedText("compose", selectedRange: NSRange(location: 7, length: 0))
            textDelegate.events.removeAll()
            view.unmarkText()

            #expect(softwareDelegate.insertedTexts == ["compose"])
            #expect(view.markedTextRange == nil)
            #expect(textDelegate.events == [
                "textWillChange",
                "selectionWillChange",
                "selectionDidChange",
                "textDidChange",
            ])
        }

        @Test
        func insertTextCommitClearsMarkedTextAndUsesDelegate() {
            let view = UITerminalView()
            let delegate = SoftwareInputDelegateSpy()
            delegate.insertResult = true
            view.softwareInputDelegate = delegate
            view.setMarkedText("preedit", selectedRange: NSRange(location: 7, length: 0))

            view.insertText("final")

            #expect(delegate.insertedTexts == ["final"])
            #expect(view.markedTextRange == nil)
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
        func hardwareSuppressionPrecedesSoftwareDelegate() {
            let view = UITerminalView()
            let delegate = SoftwareInputDelegateSpy()
            delegate.insertResult = true
            delegate.deleteResult = true
            view.softwareInputDelegate = delegate

            view.hardwareKeyHandled = true
            view.insertText("printable")
            view.hardwareKeyHandled = true
            view.deleteBackward()

            #expect(delegate.insertedTexts.isEmpty)
            #expect(delegate.deleteCallCount == 0)
            #expect(!view.hardwareKeyHandled)
        }

        @Test
        func modifiedAndDeadKeyCommitSequenceStillReachesSoftwareDelegate() {
            let view = UITerminalView()
            let delegate = SoftwareInputDelegateSpy()
            delegate.insertResult = true
            view.softwareInputDelegate = delegate

            // Modified and dead-key hardware events intentionally do not arm
            // UIKeyInput suppression; UIKit's later committed text must flow once.
            view.hardwareKeyHandled = false
            view.insertText("é")

            #expect(delegate.insertedTexts == ["é"])
            #expect(!view.hardwareKeyHandled)
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
        func accessoryVisibilityCanBeChanged() throws {
            #if !targetEnvironment(macCatalyst)
                let fixture = try SurfaceFixture()
                #expect(fixture.view.becomeFirstResponder())
                #expect(fixture.view.inputAccessoryView != nil)

                fixture.view.showsInputAccessory = false
                #expect(fixture.view.inputAccessoryView == nil)

                fixture.view.showsInputAccessory = true
                #expect(fixture.view.inputAccessoryView != nil)
            #else
                let view = UITerminalView()
                view.showsInputAccessory = false
                #expect(!view.showsInputAccessory)
            #endif
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
