import AppCore
import Foundation

public final class KeychainProviderCredentialStore: ProviderCredentialStore {
    private enum Keys {
        static let service = "com.flo.provider-credentials"
        static let credentialPoolSuffix = ".pool.v1"
    }

    private let keychain: KeychainStore

    public init(keychain: KeychainStore = .shared) {
        self.keychain = keychain
    }

    public func credential(for providerID: String) -> String? {
        let list = credentials(for: providerID)
        return list.first
    }

    public func credentials(for providerID: String) -> [String] {
        let key = normalizedKey(for: providerID)
        guard !key.isEmpty else {
            return []
        }

        do {
            if let poolData = try keychain.get(key: poolKey(for: key), service: Keys.service) {
                if let decoded = try? JSONDecoder().decode([String].self, from: poolData) {
                    let cleaned = sanitize(decoded)
                    if !cleaned.isEmpty {
                        return cleaned
                    }
                }
            }

            guard let data = try keychain.get(key: key, service: Keys.service) else {
                return []
            }
            guard let value = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty
            else {
                return []
            }
            return [value]
        } catch {
            return []
        }
    }

    public func saveCredential(_ credential: String, for providerID: String) throws {
        try saveCredentials([credential], for: providerID)
    }

    public func saveCredentials(_ credentials: [String], for providerID: String) throws {
        let key = normalizedKey(for: providerID)
        let normalized = sanitize(credentials)
        guard !key.isEmpty else {
            return
        }

        if normalized.isEmpty {
            try clearCredential(for: providerID)
            return
        }

        guard let firstData = normalized[0].data(using: .utf8) else {
            throw FloError.persistence("Could not encode provider credential.")
        }
        let poolData = try JSONEncoder().encode(normalized)

        try keychain.set(firstData, for: key, service: Keys.service)
        try keychain.set(poolData, for: poolKey(for: key), service: Keys.service)
    }

    public func clearCredential(for providerID: String) throws {
        let key = normalizedKey(for: providerID)
        guard !key.isEmpty else {
            return
        }
        try keychain.delete(key: key, service: Keys.service)
        try? keychain.delete(key: poolKey(for: key), service: Keys.service)
    }

    private func normalizedKey(for providerID: String) -> String {
        providerID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func poolKey(for normalizedProviderID: String) -> String {
        normalizedProviderID + Keys.credentialPoolSuffix
    }

    private func sanitize(_ credentials: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in credentials {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            if seen.insert(trimmed).inserted {
                result.append(trimmed)
            }
        }
        return result
    }
}
