import AppCore
import Testing

@Test
func validateAcceptsDefaultShortcuts() throws {
    try ShortcutBindingValidator.validate(DefaultShortcuts.all)
}

@Test
func validateRejectsDuplicateShortcutBindings() {
    let duplicate = KeyCombo(keyCode: 49, modifiers: [.option], keyDisplay: "Space")
    let bindings = [
        ShortcutBinding(action: .dictationHold, combo: duplicate),
        ShortcutBinding(action: .readSelectedText, combo: duplicate)
    ]

    do {
        try ShortcutBindingValidator.validate(bindings)
        Issue.record("Expected duplicate binding validation error")
    } catch {
        guard case ShortcutValidationError.duplicateBinding(let first, let second) = error else {
            Issue.record("Expected duplicateBinding error, got: \(error)")
            return
        }
        #expect(first == .dictationHold)
        #expect(second == .readSelectedText)
    }
}

@Test
func validateRejectsMissingRequiredBinding() {
    let bindings = [
        ShortcutBinding(action: .dictationHold, combo: DefaultShortcuts.dictation.combo)
    ]

    do {
        try ShortcutBindingValidator.validate(bindings)
        Issue.record("Expected missing required binding validation error")
    } catch {
        guard case ShortcutValidationError.missingRequiredBinding(let action) = error else {
            Issue.record("Expected missingRequiredBinding error, got: \(error)")
            return
        }
        #expect(action == .readSelectedText)
    }
}
