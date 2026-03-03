import Foundation

public enum DefaultShortcuts {
    public static let dictation = ShortcutBinding(
        action: .dictationHold,
        combo: KeyCombo(keyCode: 49, modifiers: [.option], keyDisplay: "Space")
    )

    public static let readSelected = ShortcutBinding(
        action: .readSelectedText,
        combo: KeyCombo(keyCode: 15, modifiers: [.option], keyDisplay: "R")
    )

    public static let all: [ShortcutBinding] = [dictation, readSelected]
}
