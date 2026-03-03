import AppCore
import Foundation

public struct ShortcutPreset: Identifiable, Hashable, Sendable {
    public let id: String
    public let combo: KeyCombo

    public init(combo: KeyCombo) {
        self.id = combo.humanReadable
        self.combo = combo
    }
}

public enum ShortcutPresetCatalog {
    public static let all: [ShortcutPreset] = [
        ShortcutPreset(combo: KeyCombo(keyCode: 49, modifiers: [.option], keyDisplay: "Space")),
        ShortcutPreset(combo: KeyCombo(keyCode: 49, modifiers: [.control, .option], keyDisplay: "Space")),
        ShortcutPreset(combo: KeyCombo(keyCode: 15, modifiers: [.option], keyDisplay: "R")),
        ShortcutPreset(combo: KeyCombo(keyCode: 14, modifiers: [.option], keyDisplay: "E")),
        ShortcutPreset(combo: KeyCombo(keyCode: 11, modifiers: [.option], keyDisplay: "B")),
        ShortcutPreset(combo: KeyCombo(keyCode: 17, modifiers: [.option], keyDisplay: "T")),
        ShortcutPreset(combo: KeyCombo(keyCode: 15, modifiers: [.control, .option], keyDisplay: "R")),
        ShortcutPreset(combo: KeyCombo(keyCode: 17, modifiers: [.control, .option], keyDisplay: "T"))
    ]

    public static func defaults(for action: ShortcutAction) -> KeyCombo {
        switch action {
        case .dictationHold:
            return DefaultShortcuts.dictation.combo
        case .readSelectedText:
            return DefaultShortcuts.readSelected.combo
        case .pushToTalkToggle:
            return KeyCombo(keyCode: 17, modifiers: [.option], keyDisplay: "T")
        }
    }
}
