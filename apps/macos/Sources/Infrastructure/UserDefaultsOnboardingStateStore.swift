import AppCore
import Foundation

public final class UserDefaultsOnboardingStateStore: OnboardingStateStore {
    private let defaults: UserDefaults
    private let key = "flo.onboarding.hotkey_confirmation.completed"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func hasCompletedHotkeyConfirmation() -> Bool {
        defaults.bool(forKey: key)
    }

    public func setHotkeyConfirmationCompleted(_ completed: Bool) {
        defaults.set(completed, forKey: key)
    }
}
