import AppCore
import Foundation

public final class UserDefaultsVoicePreferencesStore: VoicePreferencesStore {
    private struct Payload: Codable {
        let voice: String
        let speed: Double
    }

    private let defaults: UserDefaults
    private let key = "flo.voice.preferences"
    private let fallback: VoicePreferences

    public init(
        defaults: UserDefaults = .standard,
        fallback: VoicePreferences = VoicePreferences(voice: "alloy", speed: 1.0)
    ) {
        self.defaults = defaults
        self.fallback = fallback
    }

    public func load() -> VoicePreferences {
        guard let data = defaults.data(forKey: key),
              let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else {
            return fallback
        }

        return VoicePreferences(voice: payload.voice, speed: payload.speed)
    }

    public func save(_ preferences: VoicePreferences) {
        let payload = Payload(voice: preferences.voice, speed: preferences.speed)
        guard let data = try? JSONEncoder().encode(payload) else {
            return
        }
        defaults.set(data, forKey: key)
    }
}
