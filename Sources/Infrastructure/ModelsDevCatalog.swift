import Foundation

public struct ModelsDevModelEntry: Codable, Hashable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct ModelsDevProviderEntry: Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let envKeys: [String]
    public let apiBaseURL: String?
    public let models: [ModelsDevModelEntry]

    public init(
        id: String,
        name: String,
        envKeys: [String],
        apiBaseURL: String?,
        models: [ModelsDevModelEntry]
    ) {
        self.id = id
        self.name = name
        self.envKeys = envKeys
        self.apiBaseURL = apiBaseURL
        self.models = models
    }

    public var logoURL: URL? {
        guard let encodedID = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        return URL(string: "https://models.dev/logos/\(encodedID).svg")
    }
}

public struct ModelsDevCatalogSnapshot: Codable, Sendable {
    public let fetchedAt: Date
    public let providers: [ModelsDevProviderEntry]

    public init(fetchedAt: Date, providers: [ModelsDevProviderEntry]) {
        self.fetchedAt = fetchedAt
        self.providers = providers
    }

    public static let empty = ModelsDevCatalogSnapshot(fetchedAt: .distantPast, providers: [])

    public var providerByID: [String: ModelsDevProviderEntry] {
        Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
    }
}

public actor ModelsDevCatalogService {
    public static let shared = ModelsDevCatalogService()

    private static let endpoint = URL(string: "https://models.dev/api.json")!
    private static let cacheDirectoryName = "flo"
    private static let cacheFileName = "models-dev-catalog-cache.json"

    private let session: URLSession
    private let fileManager: FileManager
    private let cacheFileURL: URL
    private var inMemorySnapshot: ModelsDevCatalogSnapshot?

    public init(
        session: URLSession = .shared,
        fileManager: FileManager = .default,
        cacheFileURL: URL? = nil
    ) {
        self.session = session
        self.fileManager = fileManager
        if let cacheFileURL {
            self.cacheFileURL = cacheFileURL
        } else {
            let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first ??
                URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            self.cacheFileURL = cachesURL
                .appendingPathComponent(Self.cacheDirectoryName, isDirectory: true)
                .appendingPathComponent(Self.cacheFileName, isDirectory: false)
        }
    }

    public func loadCatalog(forceRefresh: Bool = false) async -> ModelsDevCatalogSnapshot {
        if !forceRefresh, let inMemorySnapshot {
            return inMemorySnapshot
        }

        if let remoteSnapshot = await fetchRemoteCatalog() {
            inMemorySnapshot = remoteSnapshot
            saveCachedCatalog(remoteSnapshot)
            return remoteSnapshot
        }

        if let cachedSnapshot = loadCachedCatalog() {
            inMemorySnapshot = cachedSnapshot
            return cachedSnapshot
        }

        let fallback = Self.fallbackCatalog()
        inMemorySnapshot = fallback
        return fallback
    }

    private func fetchRemoteCatalog() async -> ModelsDevCatalogSnapshot? {
        var request = URLRequest(url: Self.endpoint)
        request.timeoutInterval = 12

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
                return nil
            }
            return decodeRemoteCatalog(from: data, fetchedAt: Date())
        } catch {
            return nil
        }
    }

    private func decodeRemoteCatalog(from data: Data, fetchedAt: Date) -> ModelsDevCatalogSnapshot? {
        do {
            let decoder = JSONDecoder()
            let payload = try decoder.decode([String: ModelsDevProviderPayload].self, from: data)
            var providers: [ModelsDevProviderEntry] = []
            providers.reserveCapacity(payload.count)

            for (rawID, providerPayload) in payload {
                let id = normalizedProviderID(providerPayload.id ?? rawID)
                guard !id.isEmpty else {
                    continue
                }

                let name = nonEmpty(providerPayload.name) ?? id
                let envKeys = uniqueStrings(providerPayload.env ?? [])
                let models = decodedModels(from: providerPayload.models ?? [:])

                providers.append(
                    ModelsDevProviderEntry(
                        id: id,
                        name: name,
                        envKeys: envKeys,
                        apiBaseURL: nonEmpty(providerPayload.api),
                        models: models
                    )
                )
            }

            providers.sort {
                let byName = $0.name.localizedCaseInsensitiveCompare($1.name)
                if byName == .orderedSame {
                    return $0.id < $1.id
                }
                return byName == .orderedAscending
            }

            return ModelsDevCatalogSnapshot(fetchedAt: fetchedAt, providers: providers)
        } catch {
            return nil
        }
    }

    private func decodedModels(from payload: [String: ModelsDevModelPayload]) -> [ModelsDevModelEntry] {
        var models: [ModelsDevModelEntry] = []
        models.reserveCapacity(payload.count)

        for (rawID, modelPayload) in payload {
            let id = nonEmpty(modelPayload.id) ?? rawID
            guard !id.isEmpty else {
                continue
            }

            let name = nonEmpty(modelPayload.name) ?? id
            models.append(ModelsDevModelEntry(id: id, name: name))
        }

        models.sort {
            let byName = $0.name.localizedCaseInsensitiveCompare($1.name)
            if byName == .orderedSame {
                return $0.id < $1.id
            }
            return byName == .orderedAscending
        }

        return models
    }

    private func loadCachedCatalog() -> ModelsDevCatalogSnapshot? {
        guard let data = try? Data(contentsOf: cacheFileURL) else {
            return nil
        }

        let decoder = JSONDecoder()
        guard let decoded = try? decoder.decode(ModelsDevCatalogSnapshot.self, from: data) else {
            return nil
        }
        return decoded
    }

    private func saveCachedCatalog(_ snapshot: ModelsDevCatalogSnapshot) {
        let directoryURL = cacheFileURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(snapshot) else {
            return
        }

        try? data.write(to: cacheFileURL, options: [.atomic])
    }

    private static func fallbackCatalog() -> ModelsDevCatalogSnapshot {
        let providers = ProviderCatalog.allEntries.map { entry in
            ModelsDevProviderEntry(
                id: entry.id,
                name: entry.displayName,
                envKeys: entry.legacyEnvKeys,
                apiBaseURL: entry.apiBaseURL,
                models: []
            )
        }
        return ModelsDevCatalogSnapshot(fetchedAt: .distantPast, providers: providers)
    }

    private func normalizedProviderID(_ rawID: String) -> String {
        rawID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func uniqueStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            if seen.insert(trimmed).inserted {
                ordered.append(trimmed)
            }
        }
        return ordered
    }
}

private struct ModelsDevProviderPayload: Decodable {
    let id: String?
    let name: String?
    let env: [String]?
    let api: String?
    let models: [String: ModelsDevModelPayload]?
}

private struct ModelsDevModelPayload: Decodable {
    let id: String?
    let name: String?
}
