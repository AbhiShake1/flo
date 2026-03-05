import Foundation
import Security

public final class KeychainStore: @unchecked Sendable {
    public static let shared = KeychainStore()

    private init() {}

    public func set(_ data: Data, for key: String, service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus != errSecSuccess {
                throw KeychainError.osStatus(addStatus)
            }
            return
        }

        throw KeychainError.osStatus(updateStatus)
    }

    public func get(key: String, service: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        if status != errSecSuccess {
            throw KeychainError.osStatus(status)
        }
        return result as? Data
    }

    public func delete(key: String, service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status == errSecItemNotFound || status == errSecSuccess {
            return
        }
        throw KeychainError.osStatus(status)
    }
}

public enum KeychainError: LocalizedError {
    case osStatus(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .osStatus(let status):
            return "Keychain error: \(status)"
        }
    }
}
