import AppCore
import Foundation

public final class KeychainProviderCredentialStore: ProviderCredentialStore {
    private enum Keys {
        static let service = "com.flo.provider-credentials"
    }

    private let keychain: KeychainStore

    public init(keychain: KeychainStore = .shared) {
        self.keychain = keychain
    }

    public func credential(for providerID: String) -> String? {
        let key = normalizedKey(for: providerID)
        guard !key.isEmpty else {
            return nil
        }

        do {
            guard let data = try keychain.get(key: key, service: Keys.service) else {
                return nil
            }
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    public func saveCredential(_ credential: String, for providerID: String) throws {
        let key = normalizedKey(for: providerID)
        let trimmed = credential.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !trimmed.isEmpty else {
            throw FloError.persistence("Provider credential is empty.")
        }
        guard let data = trimmed.data(using: .utf8) else {
            throw FloError.persistence("Could not encode provider credential.")
        }
        try keychain.set(data, for: key, service: Keys.service)
    }

    public func clearCredential(for providerID: String) throws {
        let key = normalizedKey(for: providerID)
        guard !key.isEmpty else {
            return
        }
        try keychain.delete(key: key, service: Keys.service)
    }

    private func normalizedKey(for providerID: String) -> String {
        providerID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
