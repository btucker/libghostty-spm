#if canImport(UIKit)
    import Foundation
    import UIKit
    import Testing
    @testable import GhosttyTerminal

    @MainActor
    struct UIKitHostInputTests {
        @Test func hostReceivesCommittedSoftwareTextOnce() {
            let view = UITerminalView(frame: .zero)
            let delegate = HostInputProbe()
            view.softwareInputDelegate = delegate
            view.insertText("a")
            view.insertText("\n")
            view.setMarkedText("漢", selectedRange: NSRange(location: 1, length: 0))
            #expect(delegate.text == ["a", "\n"])
            view.unmarkText()
            view.deleteBackward()
            #expect(delegate.text == ["a", "\n", "漢"])
            #expect(delegate.deletes == 1)
            #expect(!view.inputHandler.hasMarkedText)
        }

        @Test func hostHardwareConsumptionSuppressesSoftwareEchoAndRelease() {
            let view = UITerminalView(frame: .zero)
            let delegate = HostInputProbe()
            view.hardwareInputDelegate = delegate
            view.softwareInputDelegate = delegate
            let press = HostInputPress(key: HostInputKey())
            view.pressesBegan([press], with: nil)
            #expect(delegate.keys.count == 1)
            #expect(delegate.keys.first?.usage == 4)
            #expect(view.hardwareKeyboard.hostHandledPresses.contains(ObjectIdentifier(press)))
            #expect(view.hardwareKeyboard.keyRepeat == nil)
            view.insertText("a")
            #expect(delegate.text.isEmpty)
            view.pressesEnded([press], with: nil)
            #expect(view.hardwareKeyboard.hostHandledPresses.isEmpty)
            #expect(!view.hardwareKeyboard.keyHandled)
            view.insertText("b")
            #expect(delegate.text == ["b"])
        }

        @Test func cancellingHostHardwarePressClearsOwnership() {
            let view = UITerminalView(frame: .zero)
            let delegate = HostInputProbe()
            view.hardwareInputDelegate = delegate
            let press = HostInputPress(key: HostInputKey())
            view.pressesBegan([press], with: nil)
            view.pressesCancelled([press], with: nil)
            #expect(view.hardwareKeyboard.hostHandledPresses.isEmpty)
            #expect(!view.hardwareKeyboard.keyHandled)
        }

        @Test func keyCommandAndPhysicalPressReachHostOnce() {
            for commandFirst in [true, false] {
                let view = UITerminalView(frame: .zero)
                let delegate = HostInputProbe()
                view.hardwareInputDelegate = delegate
                let key = HostInputKey(modifiers: .control)
                let press = HostInputPress(key: key)
                let command = UIKeyCommand(input: "a", modifierFlags: .control,
                    action: NSSelectorFromString("handleControlKeyCommand:"))
                if commandFirst { _ = view.perform(command.action, with: command) }
                view.pressesBegan([press], with: nil)
                if !commandFirst { _ = view.perform(command.action, with: command) }
                #expect(delegate.keys.count == 1)
                #expect(delegate.keys.first?.usage == 4)
                view.pressesEnded([press], with: nil)
                #expect(view.hardwareKeyboard.hostHandledPresses.isEmpty)
            }
        }

        #if !targetEnvironment(macCatalyst)
            @Test func stickyEnterAndDeleteKeepTheirModifiedKeyPath() {
                let view = UITerminalView(frame: .zero)
                let delegate = HostInputProbe()
                view.softwareInputDelegate = delegate
                view.toggleStickyModifier(.ctrl)
                view.insertText("\n")
                #expect(delegate.text.isEmpty)
                #expect(view.stickyActivation(for: .ctrl) == .inactive)
                view.toggleStickyModifier(.alt)
                view.deleteBackward()
                #expect(delegate.deletes == 0)
                #expect(view.stickyActivation(for: .alt) == .inactive)
            }
        #endif

        @Test func commandOnlyDeliveryDoesNotSuppressLaterSoftwareText() {
            let view = UITerminalView(frame: .zero)
            let delegate = HostInputProbe()
            view.hardwareInputDelegate = delegate
            view.softwareInputDelegate = delegate
            let command = UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [],
                action: NSSelectorFromString("handleEscapeKeyCommand:"))
            _ = view.perform(command.action, with: command)
            #expect(delegate.keys.count == 1)
            view.insertText("b")
            #expect(delegate.text == ["b"])
        }

        #if !targetEnvironment(macCatalyst)
            @Test func markedCompositionOwnsUnmodifiedHardwareKeys() {
                let view = UITerminalView(frame: .zero)
                let delegate = HostInputProbe()
                view.hardwareInputDelegate = delegate
                view.setMarkedText("漢", selectedRange: NSRange(location: 1, length: 0))
                let press = HostInputPress(key: HostInputKey(usage: .keyboardReturnOrEnter))
                view.pressesBegan([press], with: nil)
                #expect(delegate.keys.isEmpty)
                #expect(view.hardwareKeyboard.pressesLoanedToInputMethod.contains(press))
                view.pressesEnded([press], with: nil)
                #expect(view.hardwareKeyboard.pressesLoanedToInputMethod.isEmpty)
            }
        #endif

        @Test func hostCanOwnHardwareRepeat() {
            let view = UITerminalView(frame: .zero)
            #expect(view.automaticallyRepeatsHardwareKeys)
            view.automaticallyRepeatsHardwareKeys = false
            view.startKeyRepeat(for: HostInputPress(key: HostInputKey()))
            #expect(view.hardwareKeyboard.keyRepeat == nil)
        }

        @Test func keyboardGateAndAccessoryVisibilityRemainIndependent() {
            let view = UITerminalView(frame: .zero)
            #expect(view.canBecomeFirstResponder)
            view.isKeyboardInputEnabled = false
            #expect(!view.canBecomeFirstResponder)
            view.isKeyboardInputEnabled = true
            #expect(view.canBecomeFirstResponder)
            #if !targetEnvironment(macCatalyst) && !os(visionOS)
                #expect(view.inputAccessoryView != nil)
                view.showsInputAccessory = false
                #expect(view.inputAccessoryView == nil)
                view.showsInputAccessory = true
                #expect(view.inputAccessoryView != nil)
            #endif
        }
    }

    @MainActor
    private final class HostInputProbe: TerminalSoftwareInputDelegate, TerminalHardwareInputDelegate {
        var text: [String] = []
        var keys: [TerminalHardwareKeyEvent] = []
        var deletes = 0
        func terminalView(_ view: UITerminalView, insertText text: String) -> Bool {
            self.text.append(text)
            return true
        }
        func terminalViewDeleteBackward(_ view: UITerminalView) -> Bool {
            deletes += 1
            return true
        }
        func terminalView(_ view: UITerminalView, handleHardwareKey event: TerminalHardwareKeyEvent) -> Bool {
            keys.append(event)
            return true
        }
    }

    private final class HostInputKey: UIKey {
        override var characters: String { usage == .keyboardReturnOrEnter ? "\r" : "a" }
        override var charactersIgnoringModifiers: String { characters }
        private let flags: UIKeyModifierFlags
        private let usage: UIKeyboardHIDUsage
        init(modifiers: UIKeyModifierFlags = [], usage: UIKeyboardHIDUsage = .keyboardA) {
            flags = modifiers
            self.usage = usage
            super.init()
        }
        required init?(coder: NSCoder) { fatalError("test key does not support decoding") }
        override var modifierFlags: UIKeyModifierFlags { flags }
        override var keyCode: UIKeyboardHIDUsage { usage }
    }

    private final class HostInputPress: UIPress {
        private let inputKey: UIKey
        init(key: UIKey) {
            inputKey = key
            super.init()
        }
        override var key: UIKey? { inputKey }
    }
#endif
