import AppCore
import Foundation

public final class UserDefaultsProviderRoutingStore: ProviderRoutingStore {
    private enum Keys {
        static let payload = "flo.provider_routing_overrides.v1"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadOverrides() -> ProviderRoutingOverrides {
        guard let data = defaults.data(forKey: Keys.payload) else {
            return .default
        }

        guard let decoded = try? JSONDecoder().decode(ProviderRoutingOverrides.self, from: data) else {
            return .default
        }

        return decoded
    }

    public func saveOverrides(_ overrides: ProviderRoutingOverrides) {
        if overrides == .default {
            defaults.removeObject(forKey: Keys.payload)
            return
        }

        guard let encoded = try? JSONEncoder().encode(overrides) else {
            return
        }
        defaults.set(encoded, forKey: Keys.payload)
    }
}
