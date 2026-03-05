import AppCore
import ApplicationServices
import Carbon.HIToolbox
import Foundation

public final class SmartPasteTextInjectionService: TextInjectionService {
    private enum Metrics {
        static let unicodeChunkSize = 16
    }

    private enum FocusProbe {
        static let definitelyNonEditableContainerRoles: Set<String> = [
            "AXApplication",
            "AXMenuBar",
            "AXMenuButton",
            "AXMenuItem",
            "AXToolbar",
            "AXWindow"
        ]
    }

    public init() {}

    public func inject(text: String) throws {
        if IsSecureEventInputEnabled() {
            throw FloError.secureInputActive
        }
        guard hasFocusedTextInputTarget() else {
            throw FloError.injectionFailed
        }
        try typeText(text)
    }

    public func replaceRecentText(previousText: String, with updatedText: String) throws {
        if IsSecureEventInputEnabled() {
            throw FloError.secureInputActive
        }
        guard hasFocusedTextInputTarget() else {
            throw FloError.injectionFailed
        }

        if previousText != updatedText {
            for _ in previousText {
                sendKey(keyCode: 51) // Delete (backspace)
            }
        }

        if !updatedText.isEmpty {
            try typeText(updatedText)
        }
    }

    private func sendKey(keyCode: CGKeyCode) {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            return
        }

        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        down?.post(tap: .cghidEventTap)

        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        up?.post(tap: .cghidEventTap)
    }

    private func typeText(_ text: String) throws {
        guard !text.isEmpty else {
            return
        }

        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw FloError.injectionFailed
        }

        let codeUnits = Array(text.utf16)
        var cursor = 0
        while cursor < codeUnits.count {
            let end = min(cursor + Metrics.unicodeChunkSize, codeUnits.count)
            let chunk = Array(codeUnits[cursor..<end])
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else {
                throw FloError.injectionFailed
            }

            chunk.withUnsafeBufferPointer { buffer in
                guard let baseAddress = buffer.baseAddress else {
                    return
                }
                down.keyboardSetUnicodeString(
                    stringLength: buffer.count,
                    unicodeString: baseAddress
                )
                up.keyboardSetUnicodeString(
                    stringLength: buffer.count,
                    unicodeString: baseAddress
                )
            }

            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            cursor = end
        }
    }

    private func hasFocusedTextInputTarget() -> Bool {
        guard AXIsProcessTrusted() else {
            // Permission checks should already gate this; avoid false negatives if AX trust state races.
            return true
        }
        guard let focusedElement = focusedElement() else {
            return false
        }

        let focusedRole = stringAttribute(kAXRoleAttribute as CFString, from: focusedElement)
        if let focusedRole, FocusProbe.definitelyNonEditableContainerRoles.contains(focusedRole) {
            return false
        }

        // Favor permissive behavior to avoid false negatives in browsers/custom inputs.
        return true
    }

    private func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )
        guard focusedResult == .success, let focusedValue else {
            return nil
        }
        guard CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeDowncast(focusedValue as AnyObject, to: AXUIElement.self)
    }

    private func stringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let value else {
            return nil
        }
        return value as? String
    }

}
