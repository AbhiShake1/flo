import AppCore
import CryptoKit
import Foundation

public final class SecureSessionHistoryStore: SessionHistoryStore {
    private enum Keys {
        static let keychainService = "com.flo.history"
        static let encryptionKey = "history_encryption_key"
    }

    private let historyURL: URL
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default, baseDirectoryURL: URL? = nil) {
        self.fileManager = fileManager

        let appSupport = baseDirectoryURL
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let appDirectory = appSupport.appendingPathComponent("flo", isDirectory: true)

        if !fileManager.fileExists(atPath: appDirectory.path) {
            try? fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        }

        historyURL = appDirectory.appendingPathComponent("history.enc")
    }

    public func load() throws -> [HistoryEntry] {
        guard fileManager.fileExists(atPath: historyURL.path) else {
            return []
        }

        do {
            let encrypted = try Data(contentsOf: historyURL)
            let key = try symmetricKey()
            let sealedBox = try AES.GCM.SealedBox(combined: encrypted)
            let decrypted = try AES.GCM.open(sealedBox, using: key)
            return try JSONDecoder().decode([HistoryEntry].self, from: decrypted)
        } catch {
            if shouldResetCorruptedHistory(after: error) {
                resetCorruptedHistory()
                return []
            }
            throw error
        }
    }

    public func append(_ entry: HistoryEntry) throws {
        var entries = try load()
        entries.insert(entry, at: 0)
        let capped = Array(entries.prefix(300))
        try save(capped)
    }

    public func clear() throws {
        if fileManager.fileExists(atPath: historyURL.path) {
            try fileManager.removeItem(at: historyURL)
        }
        try? KeychainStore.shared.delete(key: Keys.encryptionKey, service: Keys.keychainService)
    }

    private func save(_ entries: [HistoryEntry]) throws {
        let plain = try JSONEncoder().encode(entries)
        let key = try symmetricKey()
        let sealed = try AES.GCM.seal(plain, using: key)

        guard let combined = sealed.combined else {
            throw FloError.persistence("Could not encode encrypted history payload")
        }

        try combined.write(to: historyURL, options: .atomic)
    }

    private func symmetricKey() throws -> SymmetricKey {
        if let keyData = try KeychainStore.shared.get(key: Keys.encryptionKey, service: Keys.keychainService) {
            return SymmetricKey(data: keyData)
        }

        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        try KeychainStore.shared.set(data, for: Keys.encryptionKey, service: Keys.keychainService)
        return key
    }

    private func shouldResetCorruptedHistory(after error: Error) -> Bool {
        if error is CryptoKitError || error is DecodingError {
            return true
        }

        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadCorruptFileError {
            return true
        }

        return false
    }

    private func resetCorruptedHistory() {
        if fileManager.fileExists(atPath: historyURL.path) {
            try? fileManager.removeItem(at: historyURL)
        }
        try? KeychainStore.shared.delete(key: Keys.encryptionKey, service: Keys.keychainService)
    }
}
