import Foundation

public enum ShortcutValidationError: LocalizedError, Equatable, Sendable {
    case duplicateBinding(ShortcutAction, ShortcutAction)
    case missingRequiredBinding(ShortcutAction)

    public var errorDescription: String? {
        switch self {
        case .duplicateBinding(let first, let second):
            return "Shortcut conflict between \(first.displayName) and \(second.displayName)."
        case .missingRequiredBinding(let action):
            return "Missing shortcut binding for \(action.displayName)."
        }
    }
}

public enum ShortcutBindingValidator {
    public static func validate(_ bindings: [ShortcutBinding]) throws {
        let enabledBindings = bindings.filter(\.enabled)
        var seen: [KeyCombo: ShortcutAction] = [:]

        for binding in enabledBindings {
            if let existing = seen[binding.combo], existing != binding.action {
                throw ShortcutValidationError.duplicateBinding(existing, binding.action)
            }
            seen[binding.combo] = binding.action
        }

        let requiredActions: [ShortcutAction] = [.dictationHold, .readSelectedText]
        for action in requiredActions where !bindings.contains(where: { $0.action == action }) {
            throw ShortcutValidationError.missingRequiredBinding(action)
        }
    }
}
