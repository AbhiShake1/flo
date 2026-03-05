import AppCore
import Foundation

public final class UserDefaultsDictationRewritePreferencesStore: DictationRewritePreferencesStore {
    private enum Keys {
        static let storage = "flo.dictation.rewrite.preferences.v1"
    }

    private let defaults: UserDefaults
    private let fallback: DictationRewritePreferences
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        defaults: UserDefaults = .standard,
        fallback: DictationRewritePreferences = .default
    ) {
        self.defaults = defaults
        self.fallback = fallback
    }

    public func load() -> DictationRewritePreferences {
        guard let data = defaults.data(forKey: Keys.storage) else {
            return fallback
        }

        return (try? decoder.decode(DictationRewritePreferences.self, from: data)) ?? fallback
    }

    public func save(_ preferences: DictationRewritePreferences) {
        guard let data = try? encoder.encode(preferences) else {
            return
        }
        defaults.set(data, forKey: Keys.storage)
    }
}
