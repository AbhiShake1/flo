import AppCore
import AppKit
import Foundation

public final class MacSelectionReaderService: SelectionReaderService {
    public init() {}

    public func getSelectedText() throws -> String {
        if let selectedByAccessibility = SelectionProbe.selectedText() {
            return selectedByAccessibility
        }

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        let sentinel = "__flo-selection-\(UUID().uuidString)__"

        pasteboard.clearContents()
        _ = pasteboard.setString(sentinel, forType: .string)
        Thread.sleep(forTimeInterval: 0.01)

        sendCommandKey(keyCode: 8) // C

        let maxAttempts = 60
        var extracted: String?

        for _ in 0..<maxAttempts {
            if let string = pasteboard.string(forType: .string),
               string != sentinel,
               !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                extracted = string
                break
            }
            Thread.sleep(forTimeInterval: 0.02)
        }

        snapshot.restore(to: pasteboard)

        guard let extracted else {
            throw FloError.noSelectedText
        }

        return extracted
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
