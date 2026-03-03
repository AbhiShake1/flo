import AppCore
import AppKit
import Carbon.HIToolbox
import Foundation

public final class SmartPasteTextInjectionService: TextInjectionService {
    public init() {}

    public func inject(text: String) throws {
        if IsSecureEventInputEnabled() {
            throw FloError.secureInputActive
        }

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw FloError.injectionFailed
        }

        sendCommandKey(keyCode: 9) // V

        Thread.sleep(forTimeInterval: 0.12)
        snapshot.restore(to: pasteboard)
    }

    public func replaceRecentText(previousText: String, with updatedText: String) throws {
        if IsSecureEventInputEnabled() {
            throw FloError.secureInputActive
        }

        if previousText != updatedText {
            for _ in previousText {
                sendKey(keyCode: 51) // Delete (backspace)
            }
        }

        if !updatedText.isEmpty {
            try inject(text: updatedText)
        }
    }

    private func sendCommandKey(keyCode: CGKeyCode) {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            return
        }

        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        down?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)

        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        up?.flags = .maskCommand
        up?.post(tap: .cghidEventTap)
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
}

private struct PasteboardSnapshot {
    let items: [NSPasteboardItem]

    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let copiedItems = (pasteboard.pasteboardItems ?? []).map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
        return PasteboardSnapshot(items: copiedItems)
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }
}
