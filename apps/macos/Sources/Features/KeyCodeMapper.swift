import AppCore
import Foundation

public enum KeyCodeMapper {
    private static let map: [String: UInt16] = [
        "A": 0, "S": 1, "D": 2, "F": 3, "H": 4, "G": 5,
        "Z": 6, "X": 7, "C": 8, "V": 9, "B": 11, "Q": 12,
        "W": 13, "E": 14, "R": 15, "Y": 16, "T": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
        "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
        "]": 30, "O": 31, "U": 32, "[": 33, "I": 34, "P": 35,
        "RETURN": 36, "L": 37, "J": 38, "'": 39, "K": 40,
        ";": 41, "\\": 42, ",": 43, "/": 44, "N": 45, "M": 46,
        ".": 47, "TAB": 48, "SPACE": 49, "`": 50, "DELETE": 51,
        "ESC": 53
    ]

    public static func combo(for keyInput: String, modifiers: ShortcutModifiers) -> KeyCombo? {
        let normalized = keyInput
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        guard let keyCode = map[normalized], !normalized.isEmpty else {
            return nil
        }

        let display: String
        switch normalized {
        case "SPACE":
            display = "Space"
        case "RETURN":
            display = "Return"
        case "TAB":
            display = "Tab"
        case "ESC":
            display = "Esc"
        default:
            display = normalized
        }

        return KeyCombo(keyCode: keyCode, modifiers: modifiers, keyDisplay: display)
    }
}
