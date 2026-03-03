import Foundation
import AppCore

public struct AIProvider: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init?(rawValue: String) {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else {
            return nil
        }
        self.rawValue = normalized
    }

    public init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private init(_ value: String) {
        self.rawValue = value
    }

    public static let openai = AIProvider("openai")
    public static let gemini = AIProvider("gemini")
    public static let google = AIProvider("google")
    public static let openrouter = AIProvider("openrouter")
    public static let groq = AIProvider("groq")
    public static let xai = AIProvider("xai")
    public static let deepinfra = AIProvider("deepinfra")
    public static let together = AIProvider("together")
    public static let togetherai = AIProvider("togetherai")
    public static let perplexity = AIProvider("perplexity")

    public static var allCases: [AIProvider] {
        ProviderCatalog.allProviders
    }

    public var displayName: String {
        if let entry = ProviderCatalog.entry(for: self) {
            return entry.displayName
        }
        return rawValue
    }

    public var supportsOAuth: Bool {
        self == .openai
    }

    public var defaultEnvKeyName: String {
        "FLO_\(Self.envToken(from: rawValue))_API_KEY"
    }

    public var defaultEnvKeysName: String {
        "FLO_\(Self.envToken(from: rawValue))_API_KEYS"
    }

    private static func envToken(from raw: String) -> String {
        raw.uppercased().map { ch in
            if ("A"..."Z").contains(ch) || ("0"..."9").contains(ch) {
                return ch
            }
            return "_"
        }.reduce(into: "") { $0.append($1) }
    }
}

public struct ProviderRuntimeConfiguration: Sendable {
    public struct Capabilities: Sendable {
        public let transcription: Bool
        public let tts: Bool
        public let rewrite: Bool

        public init(transcription: Bool, tts: Bool, rewrite: Bool) {
            self.transcription = transcription
            self.tts = tts
            self.rewrite = rewrite
        }
    }

    public let provider: AIProvider
    public let transcriptionURL: URL
    public let ttsURL: URL
    public let rewriteURL: URL
    public let transcriptionModel: String
    public let ttsModel: String
    public let rewriteModel: String
    public let ttsVoice: String
    public let ttsSpeed: Double
    public let capabilities: Capabilities

    public init(
        provider: AIProvider,
        transcriptionURL: URL,
        ttsURL: URL,
        rewriteURL: URL,
        transcriptionModel: String,
        ttsModel: String,
        rewriteModel: String,
        ttsVoice: String,
        ttsSpeed: Double,
        capabilities: Capabilities = Capabilities(transcription: true, tts: true, rewrite: true)
    ) {
        self.provider = provider
        self.transcriptionURL = transcriptionURL
        self.ttsURL = ttsURL
        self.rewriteURL = rewriteURL
        self.transcriptionModel = transcriptionModel
        self.ttsModel = ttsModel
        self.rewriteModel = rewriteModel
        self.ttsVoice = ttsVoice
        self.ttsSpeed = ttsSpeed
        self.capabilities = capabilities
    }
}

public struct ProviderFailoverPolicy: Sendable {
    public let allowCrossProviderFallback: Bool
    public let maxAttempts: Int
    public let failureThreshold: Int
    public let cooldownSeconds: Int
    public let allowedProviders: Set<AIProvider>?

    public init(
        allowCrossProviderFallback: Bool,
        maxAttempts: Int,
        failureThreshold: Int,
        cooldownSeconds: Int,
        allowedProviders: Set<AIProvider>? = nil
    ) {
        self.allowCrossProviderFallback = allowCrossProviderFallback
        self.maxAttempts = max(1, maxAttempts)
        self.failureThreshold = max(1, failureThreshold)
        self.cooldownSeconds = max(0, cooldownSeconds)
        self.allowedProviders = allowedProviders
    }
}

public struct OAuthConfiguration: Sendable {
    public static let defaultAuthorizeURL = URL(string: "https://auth.openai.com/oauth/authorize")!
    public static let defaultTokenURL = URL(string: "https://auth.openai.com/oauth/token")!
    public static let defaultClientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    public static let defaultRedirectURI = "http://localhost:1455/auth/callback"
    public static let defaultScopes = "openid profile email offline_access"
    public static let defaultOriginator = "pi"

    public let authorizeURL: URL
    public let tokenURL: URL
    public let clientID: String
    public let clientSecret: String?
    public let redirectURI: String
    public let scopes: String
    public let originator: String
    public let allowedHosts: Set<String>

    public init(
        authorizeURL: URL,
        tokenURL: URL,
        clientID: String,
        clientSecret: String? = nil,
        redirectURI: String,
        scopes: String,
        originator: String = OAuthConfiguration.defaultOriginator,
        allowedHosts: Set<String>? = nil
    ) {
        self.authorizeURL = authorizeURL
        self.tokenURL = tokenURL
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.redirectURI = redirectURI
        self.scopes = scopes
        self.originator = originator
        self.allowedHosts = allowedHosts ?? Set([authorizeURL.host, tokenURL.host].compactMap { $0 })
    }
}

public struct FloConfiguration: Sendable {
    public let provider: AIProvider
    public let providerOrder: [AIProvider]
    public let providerConfigurations: [AIProvider: ProviderRuntimeConfiguration]
    public let providerCredentialPool: [AIProvider: [String]]

    public let transcriptionURL: URL
    public let ttsURL: URL
    public let rewriteURL: URL
    public let openAIApiKey: String?
    public let geminiApiKey: String?
    public let transcriptionModel: String
    public let ttsModel: String
    public let rewriteModel: String
    public let ttsVoice: String
    public let ttsSpeed: Double
    public let maxTTSCharactersPerChunk: Int
    public let retainAudioDebugArtifacts: Bool
    public let hostAllowlist: Set<String>
    public let featureFlags: FeatureFlags
    public let manualUpdateURL: URL?
    public let oauth: OAuthConfiguration?
    public let failoverPolicy: ProviderFailoverPolicy

    public init(
        provider: AIProvider = .openai,
        transcriptionURL: URL,
        ttsURL: URL,
        rewriteURL: URL,
        openAIApiKey: String?,
        geminiApiKey: String? = nil,
        transcriptionModel: String,
        ttsModel: String,
        rewriteModel: String,
        ttsVoice: String,
        ttsSpeed: Double,
        maxTTSCharactersPerChunk: Int,
        retainAudioDebugArtifacts: Bool,
        hostAllowlist: Set<String>,
        featureFlags: FeatureFlags,
        manualUpdateURL: URL?,
        oauth: OAuthConfiguration?,
        failoverPolicy: ProviderFailoverPolicy = ProviderFailoverPolicy(
            allowCrossProviderFallback: true,
            maxAttempts: 8,
            failureThreshold: 2,
            cooldownSeconds: 60
        ),
        providerOrder: [AIProvider]? = nil,
        providerConfigurations: [AIProvider: ProviderRuntimeConfiguration]? = nil,
        providerCredentialPool: [AIProvider: [String]]? = nil
    ) {
        let primaryConfiguration = ProviderRuntimeConfiguration(
            provider: provider,
            transcriptionURL: transcriptionURL,
            ttsURL: ttsURL,
            rewriteURL: rewriteURL,
            transcriptionModel: transcriptionModel,
            ttsModel: ttsModel,
            rewriteModel: rewriteModel,
            ttsVoice: ttsVoice,
            ttsSpeed: ttsSpeed
        )

        var normalizedConfigurations: [AIProvider: ProviderRuntimeConfiguration] = providerConfigurations ?? [:]
        normalizedConfigurations[provider] = normalizedConfigurations[provider] ?? primaryConfiguration

        var normalizedCredentialPool = Self.cleanCredentialPool(providerCredentialPool ?? [:])
        if let openAIApiKey = Self.nonEmpty(openAIApiKey) {
            normalizedCredentialPool[.openai] = Self.uniquePreservingOrder([openAIApiKey] + (normalizedCredentialPool[.openai] ?? []))
        }
        if let geminiApiKey = Self.nonEmpty(geminiApiKey) {
            normalizedCredentialPool[.gemini] = Self.uniquePreservingOrder([geminiApiKey] + (normalizedCredentialPool[.gemini] ?? []))
        }

        var normalizedOrder = Self.normalizedProviders(providerOrder ?? [provider])
        for candidate in AIProvider.allCases {
            if normalizedCredentialPool[candidate]?.isEmpty == false, !normalizedOrder.contains(candidate) {
                normalizedOrder.append(candidate)
            }
        }
        if normalizedOrder.isEmpty {
            normalizedOrder = [provider]
        }

        let activeProvider = normalizedOrder.first ?? provider
        let activeConfiguration = normalizedConfigurations[activeProvider] ?? primaryConfiguration

        self.provider = activeProvider
        self.providerOrder = normalizedOrder
        self.providerConfigurations = normalizedConfigurations
        self.providerCredentialPool = normalizedCredentialPool

        self.transcriptionURL = activeConfiguration.transcriptionURL
        self.ttsURL = activeConfiguration.ttsURL
        self.rewriteURL = activeConfiguration.rewriteURL
        self.openAIApiKey = normalizedCredentialPool[.openai]?.first
        self.geminiApiKey = normalizedCredentialPool[.gemini]?.first
        self.transcriptionModel = activeConfiguration.transcriptionModel
        self.ttsModel = activeConfiguration.ttsModel
        self.rewriteModel = activeConfiguration.rewriteModel
        self.ttsVoice = activeConfiguration.ttsVoice
        self.ttsSpeed = activeConfiguration.ttsSpeed
        self.maxTTSCharactersPerChunk = maxTTSCharactersPerChunk
        self.retainAudioDebugArtifacts = retainAudioDebugArtifacts
        self.hostAllowlist = hostAllowlist
        self.featureFlags = featureFlags
        self.manualUpdateURL = manualUpdateURL
        self.oauth = oauth
        self.failoverPolicy = failoverPolicy
    }

    public var localCredentialToken: String? {
        credentials(for: provider).first
    }

    public var providerDisplayName: String {
        provider.displayName
    }

    public func credentials(for provider: AIProvider) -> [String] {
        providerCredentialPool[provider] ?? []
    }

    public func runtimeConfiguration(for provider: AIProvider) -> ProviderRuntimeConfiguration? {
        providerConfigurations[provider]
    }

    public func supportsTranscription(for provider: AIProvider) -> Bool {
        providerConfigurations[provider]?.capabilities.transcription == true
    }

    public func supportsTTS(for provider: AIProvider) -> Bool {
        providerConfigurations[provider]?.capabilities.tts == true
    }

    public func supportsRewrite(for provider: AIProvider) -> Bool {
        providerConfigurations[provider]?.capabilities.rewrite == true
    }

    public func scoped(to provider: AIProvider) -> FloConfiguration {
        guard let target = providerConfigurations[provider] else {
            return self
        }

        return FloConfiguration(
            provider: provider,
            transcriptionURL: target.transcriptionURL,
            ttsURL: target.ttsURL,
            rewriteURL: target.rewriteURL,
            openAIApiKey: providerCredentialPool[.openai]?.first,
            geminiApiKey: providerCredentialPool[.gemini]?.first,
            transcriptionModel: target.transcriptionModel,
            ttsModel: target.ttsModel,
            rewriteModel: target.rewriteModel,
            ttsVoice: target.ttsVoice,
            ttsSpeed: target.ttsSpeed,
            maxTTSCharactersPerChunk: maxTTSCharactersPerChunk,
            retainAudioDebugArtifacts: retainAudioDebugArtifacts,
            hostAllowlist: hostAllowlist,
            featureFlags: featureFlags,
            manualUpdateURL: manualUpdateURL,
            oauth: oauth,
            failoverPolicy: failoverPolicy,
            providerOrder: providerOrder,
            providerConfigurations: providerConfigurations,
            providerCredentialPool: providerCredentialPool
        )
    }

    public func withPrependedCredential(_ credential: String, for provider: AIProvider) -> FloConfiguration {
        let trimmed = credential.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return self
        }

        var updatedPool = providerCredentialPool
        let merged = [trimmed] + (updatedPool[provider] ?? [])
        updatedPool[provider] = Self.uniquePreservingOrder(merged)

        return FloConfiguration(
            provider: self.provider,
            transcriptionURL: self.transcriptionURL,
            ttsURL: self.ttsURL,
            rewriteURL: self.rewriteURL,
            openAIApiKey: updatedPool[.openai]?.first,
            geminiApiKey: updatedPool[.gemini]?.first,
            transcriptionModel: self.transcriptionModel,
            ttsModel: self.ttsModel,
            rewriteModel: self.rewriteModel,
            ttsVoice: self.ttsVoice,
            ttsSpeed: self.ttsSpeed,
            maxTTSCharactersPerChunk: self.maxTTSCharactersPerChunk,
            retainAudioDebugArtifacts: self.retainAudioDebugArtifacts,
            hostAllowlist: self.hostAllowlist,
            featureFlags: self.featureFlags,
            manualUpdateURL: self.manualUpdateURL,
            oauth: self.oauth,
            failoverPolicy: self.failoverPolicy,
            providerOrder: self.providerOrder,
            providerConfigurations: self.providerConfigurations,
            providerCredentialPool: updatedPool
        )
    }

    public func withCredentialPool(_ credentials: [String], for provider: AIProvider) -> FloConfiguration {
        var updatedPool = providerCredentialPool
        updatedPool[provider] = Self.uniquePreservingOrder(
            credentials
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )

        return FloConfiguration(
            provider: self.provider,
            transcriptionURL: self.transcriptionURL,
            ttsURL: self.ttsURL,
            rewriteURL: self.rewriteURL,
            openAIApiKey: updatedPool[.openai]?.first,
            geminiApiKey: updatedPool[.gemini]?.first,
            transcriptionModel: self.transcriptionModel,
            ttsModel: self.ttsModel,
            rewriteModel: self.rewriteModel,
            ttsVoice: self.ttsVoice,
            ttsSpeed: self.ttsSpeed,
            maxTTSCharactersPerChunk: self.maxTTSCharactersPerChunk,
            retainAudioDebugArtifacts: self.retainAudioDebugArtifacts,
            hostAllowlist: self.hostAllowlist,
            featureFlags: self.featureFlags,
            manualUpdateURL: self.manualUpdateURL,
            oauth: self.oauth,
            failoverPolicy: self.failoverPolicy,
            providerOrder: self.providerOrder,
            providerConfigurations: self.providerConfigurations,
            providerCredentialPool: updatedPool
        )
    }

    public func withProviderOrder(_ order: [AIProvider]) -> FloConfiguration {
        let normalizedOrder = Self.normalizedProviders(order)
        return FloConfiguration(
            provider: normalizedOrder.first ?? self.provider,
            transcriptionURL: self.transcriptionURL,
            ttsURL: self.ttsURL,
            rewriteURL: self.rewriteURL,
            openAIApiKey: self.providerCredentialPool[.openai]?.first,
            geminiApiKey: self.providerCredentialPool[.gemini]?.first,
            transcriptionModel: self.transcriptionModel,
            ttsModel: self.ttsModel,
            rewriteModel: self.rewriteModel,
            ttsVoice: self.ttsVoice,
            ttsSpeed: self.ttsSpeed,
            maxTTSCharactersPerChunk: self.maxTTSCharactersPerChunk,
            retainAudioDebugArtifacts: self.retainAudioDebugArtifacts,
            hostAllowlist: self.hostAllowlist,
            featureFlags: self.featureFlags,
            manualUpdateURL: self.manualUpdateURL,
            oauth: self.oauth,
            failoverPolicy: self.failoverPolicy,
            providerOrder: normalizedOrder.isEmpty ? self.providerOrder : normalizedOrder,
            providerConfigurations: self.providerConfigurations,
            providerCredentialPool: self.providerCredentialPool
        )
    }

    public func withFailoverPolicy(_ policy: ProviderFailoverPolicy) -> FloConfiguration {
        FloConfiguration(
            provider: self.provider,
            transcriptionURL: self.transcriptionURL,
            ttsURL: self.ttsURL,
            rewriteURL: self.rewriteURL,
            openAIApiKey: self.providerCredentialPool[.openai]?.first,
            geminiApiKey: self.providerCredentialPool[.gemini]?.first,
            transcriptionModel: self.transcriptionModel,
            ttsModel: self.ttsModel,
            rewriteModel: self.rewriteModel,
            ttsVoice: self.ttsVoice,
            ttsSpeed: self.ttsSpeed,
            maxTTSCharactersPerChunk: self.maxTTSCharactersPerChunk,
            retainAudioDebugArtifacts: self.retainAudioDebugArtifacts,
            hostAllowlist: self.hostAllowlist,
            featureFlags: self.featureFlags,
            manualUpdateURL: self.manualUpdateURL,
            oauth: self.oauth,
            failoverPolicy: policy,
            providerOrder: self.providerOrder,
            providerConfigurations: self.providerConfigurations,
            providerCredentialPool: self.providerCredentialPool
        )
    }

    public func applyingRoutingOverrides(_ overrides: ProviderRoutingOverrides) -> FloConfiguration {
        let overrideOrder = Self.normalizedProviders(
            overrides.providerOrder.compactMap(AIProvider.init(rawValue:))
        )
        var resolvedOrder = overrideOrder.isEmpty ? self.providerOrder : overrideOrder
        if resolvedOrder.isEmpty {
            resolvedOrder = [self.provider]
        }

        let overrideAllowedProviders = overrides.allowedProviders.map {
            Set($0.compactMap(AIProvider.init(rawValue:)))
        }
        let resolvedAllowedProviders: Set<AIProvider>? = {
            if let overrideAllowedProviders {
                return overrideAllowedProviders.isEmpty ? nil : overrideAllowedProviders
            }
            return self.failoverPolicy.allowedProviders
        }()

        if let resolvedAllowedProviders {
            resolvedOrder = resolvedOrder.filter { resolvedAllowedProviders.contains($0) }
        }
        if resolvedOrder.isEmpty, let resolvedAllowedProviders {
            resolvedOrder = self.providerOrder.filter { resolvedAllowedProviders.contains($0) }
        }
        if resolvedOrder.isEmpty {
            resolvedOrder = [self.provider]
        }

        let mergedPolicy = ProviderFailoverPolicy(
            allowCrossProviderFallback: overrides.allowCrossProviderFallback ?? self.failoverPolicy.allowCrossProviderFallback,
            maxAttempts: overrides.maxAttempts ?? self.failoverPolicy.maxAttempts,
            failureThreshold: overrides.failureThreshold ?? self.failoverPolicy.failureThreshold,
            cooldownSeconds: overrides.cooldownSeconds ?? self.failoverPolicy.cooldownSeconds,
            allowedProviders: resolvedAllowedProviders
        )

        return self.withFailoverPolicy(mergedPolicy)
            .withProviderOrder(resolvedOrder)
    }

    public static func loadFromEnvironment(_ env: [String: String] = ProcessInfo.processInfo.environment) -> FloConfiguration {
        let selectedProvider = AIProvider(
            rawValue: (env["FLO_AI_PROVIDER"] ?? "openai")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        ) ?? .openai

        var credentialPool: [AIProvider: [String]] = [:]
        for provider in AIProvider.allCases {
            let primaryValue = env[primaryCredentialEnvKey(for: provider)]
            let legacyValues = legacyCredentialEnvKeys(for: provider).map { env[$0] }
            let pool = parseCredentialPool(
                csvValue: env[csvCredentialEnvKey(for: provider)],
                fallbackValues: [primaryValue] + legacyValues
            )
            if !pool.isEmpty {
                credentialPool[provider] = pool
            }
        }

        let providerConfigurations = Dictionary(
            uniqueKeysWithValues: AIProvider.allCases.map { provider in
                (provider, providerConfiguration(for: provider, env: env))
            }
        )

        var providerOrder = normalizedProviders(
            parseProviders(env["FLO_AI_PROVIDER_ORDER"] ?? env["FLO_AI_PROVIDERS"])
        )
        if providerOrder.isEmpty {
            providerOrder = [selectedProvider]
        }

        for candidate in AIProvider.allCases {
            if credentialPool[candidate]?.isEmpty == false, !providerOrder.contains(candidate) {
                providerOrder.append(candidate)
            }
        }

        let maxTTSCharactersPerChunk = Int(env["FLO_TTS_CHUNK_SIZE"] ?? "1500") ?? 1500
        let retainAudioDebugArtifacts = (env["FLO_RETAIN_AUDIO_DEBUG"] ?? "false").lowercased() == "true"
        let manualUpdateURL = env["FLO_MANUAL_UPDATE_URL"].flatMap(URL.init(string:))

        let featureFlags = FeatureFlags(
            enableGlobalHotkeys: parseBoolean(env["FLO_FEATURE_GLOBAL_HOTKEYS"], defaultValue: true),
            enableDictation: parseBoolean(env["FLO_FEATURE_DICTATION"], defaultValue: true),
            enableReadAloud: parseBoolean(env["FLO_FEATURE_READ_ALOUD"], defaultValue: true)
        )

        let explicitAllowlist = Set(
            (env["FLO_HOST_ALLOWLIST"] ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )

        var hostAllowlist = explicitAllowlist
        for provider in providerOrder {
            guard let runtime = providerConfigurations[provider] else {
                continue
            }
            if runtime.capabilities.transcription, let host = runtime.transcriptionURL.host?.lowercased() {
                hostAllowlist.insert(host)
            }
            if runtime.capabilities.tts, let host = runtime.ttsURL.host?.lowercased() {
                hostAllowlist.insert(host)
            }
            if runtime.capabilities.rewrite, let host = runtime.rewriteURL.host?.lowercased() {
                hostAllowlist.insert(host)
            }
        }

        let oauth: OAuthConfiguration?
        let oauthEnabled = parseBoolean(
            env["FLO_CHATGPT_OAUTH_ENABLED"],
            defaultValue: providerOrder.contains(.openai)
        )
        if oauthEnabled && providerOrder.contains(.openai) {
            let authorizeURL = URL(
                string: nonEmpty(env["FLO_CHATGPT_AUTH_URL"]) ?? OAuthConfiguration.defaultAuthorizeURL.absoluteString
            ) ?? OAuthConfiguration.defaultAuthorizeURL
            let tokenURL = URL(
                string: nonEmpty(env["FLO_CHATGPT_TOKEN_URL"]) ?? OAuthConfiguration.defaultTokenURL.absoluteString
            ) ?? OAuthConfiguration.defaultTokenURL

            oauth = OAuthConfiguration(
                authorizeURL: authorizeURL,
                tokenURL: tokenURL,
                clientID: nonEmpty(env["FLO_CHATGPT_CLIENT_ID"]) ?? OAuthConfiguration.defaultClientID,
                clientSecret: nonEmpty(env["FLO_CHATGPT_CLIENT_SECRET"]),
                redirectURI: nonEmpty(env["FLO_CHATGPT_REDIRECT_URI"]) ?? OAuthConfiguration.defaultRedirectURI,
                scopes: nonEmpty(env["FLO_CHATGPT_SCOPES"]) ?? OAuthConfiguration.defaultScopes,
                originator: nonEmpty(env["FLO_CHATGPT_ORIGINATOR"]) ?? OAuthConfiguration.defaultOriginator
            )
            if let oauth {
                hostAllowlist.formUnion(oauth.allowedHosts.map { $0.lowercased() })
            }
        } else {
            oauth = nil
        }

        let failoverPolicy = ProviderFailoverPolicy(
            allowCrossProviderFallback: parseBoolean(env["FLO_FAILOVER_ALLOW_CROSS_PROVIDER"], defaultValue: true),
            maxAttempts: Int(nonEmpty(env["FLO_FAILOVER_MAX_ATTEMPTS"]) ?? "8") ?? 8,
            failureThreshold: Int(nonEmpty(env["FLO_FAILOVER_FAILURE_THRESHOLD"]) ?? "2") ?? 2,
            cooldownSeconds: Int(nonEmpty(env["FLO_FAILOVER_COOLDOWN_SECONDS"]) ?? "60") ?? 60,
            allowedProviders: {
                let parsed = normalizedProviders(parseProviders(env["FLO_FAILOVER_ALLOWED_PROVIDERS"]))
                if parsed.isEmpty {
                    return nil
                }
                return Set(parsed)
            }()
        )

        let activeProvider = providerOrder.first ?? selectedProvider
        let activeRuntime = providerConfigurations[activeProvider] ?? providerConfiguration(for: activeProvider, env: env)

        return FloConfiguration(
            provider: activeProvider,
            transcriptionURL: activeRuntime.transcriptionURL,
            ttsURL: activeRuntime.ttsURL,
            rewriteURL: activeRuntime.rewriteURL,
            openAIApiKey: credentialPool[.openai]?.first,
            geminiApiKey: credentialPool[.gemini]?.first,
            transcriptionModel: activeRuntime.transcriptionModel,
            ttsModel: activeRuntime.ttsModel,
            rewriteModel: activeRuntime.rewriteModel,
            ttsVoice: activeRuntime.ttsVoice,
            ttsSpeed: activeRuntime.ttsSpeed,
            maxTTSCharactersPerChunk: maxTTSCharactersPerChunk,
            retainAudioDebugArtifacts: retainAudioDebugArtifacts,
            hostAllowlist: hostAllowlist,
            featureFlags: featureFlags,
            manualUpdateURL: manualUpdateURL,
            oauth: oauth,
            failoverPolicy: failoverPolicy,
            providerOrder: providerOrder,
            providerConfigurations: providerConfigurations,
            providerCredentialPool: credentialPool
        )
    }

    public func isAllowedHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else {
            return false
        }
        return hostAllowlist.contains(host)
    }

    private static func providerConfiguration(for provider: AIProvider, env: [String: String]) -> ProviderRuntimeConfiguration {
        if provider == .openai {
            let transcriptionModel =
                nonEmpty(env["FLO_TRANSCRIPTION_MODEL"]) ??
                nonEmpty(env["FLO_OPENAI_TRANSCRIPTION_MODEL"]) ??
                "gpt-4o-mini-transcribe"
            let ttsModel =
                nonEmpty(env["FLO_TTS_MODEL"]) ??
                nonEmpty(env["FLO_OPENAI_TTS_MODEL"]) ??
                "gpt-4o-mini-tts"
            let rewriteModel =
                nonEmpty(env["FLO_REWRITE_MODEL"]) ??
                nonEmpty(env["FLO_OPENAI_REWRITE_MODEL"]) ??
                "gpt-4o-mini"
            let ttsVoice = nonEmpty(env["FLO_TTS_VOICE"]) ?? nonEmpty(env["FLO_OPENAI_TTS_VOICE"]) ?? "alloy"
            let ttsSpeed = Double(
                nonEmpty(env["FLO_TTS_SPEED"]) ??
                nonEmpty(env["FLO_OPENAI_TTS_SPEED"]) ??
                "1.0"
            ) ?? 1.0

            let transcriptionURL = URL(
                string: env["FLO_OPENAI_TRANSCRIPTION_URL"] ?? "https://api.openai.com/v1/audio/transcriptions"
            )!
            let ttsURL = URL(
                string: env["FLO_OPENAI_TTS_URL"] ?? "https://api.openai.com/v1/audio/speech"
            )!
            let rewriteURL = URL(
                string: env["FLO_OPENAI_REWRITE_URL"] ?? "https://api.openai.com/v1/chat/completions"
            )!

            return ProviderRuntimeConfiguration(
                provider: .openai,
                transcriptionURL: transcriptionURL,
                ttsURL: ttsURL,
                rewriteURL: rewriteURL,
                transcriptionModel: transcriptionModel,
                ttsModel: ttsModel,
                rewriteModel: rewriteModel,
                ttsVoice: ttsVoice,
                ttsSpeed: ttsSpeed
            )

        }

        if provider == .gemini || provider == .google {
            let providerToken = envToken(for: provider)
            let alternateToken = provider == .gemini ? "GOOGLE" : "GEMINI"
            let transcriptionModel =
                nonEmpty(env["FLO_TRANSCRIPTION_MODEL"]) ??
                nonEmpty(env["FLO_\(providerToken)_TRANSCRIPTION_MODEL"]) ??
                nonEmpty(env["FLO_\(alternateToken)_TRANSCRIPTION_MODEL"]) ??
                "gemini-3-flash-preview"
            let ttsModel =
                nonEmpty(env["FLO_TTS_MODEL"]) ??
                nonEmpty(env["FLO_\(providerToken)_TTS_MODEL"]) ??
                nonEmpty(env["FLO_\(alternateToken)_TTS_MODEL"]) ??
                "gemini-2.5-flash-preview-tts"
            let rewriteModel =
                nonEmpty(env["FLO_REWRITE_MODEL"]) ??
                nonEmpty(env["FLO_\(providerToken)_REWRITE_MODEL"]) ??
                nonEmpty(env["FLO_\(alternateToken)_REWRITE_MODEL"]) ??
                "gemini-2.0-flash"
            let ttsVoice =
                nonEmpty(env["FLO_TTS_VOICE"]) ??
                nonEmpty(env["FLO_\(providerToken)_TTS_VOICE"]) ??
                nonEmpty(env["FLO_\(alternateToken)_TTS_VOICE"]) ??
                "Kore"
            let ttsSpeed = Double(
                nonEmpty(env["FLO_TTS_SPEED"]) ??
                nonEmpty(env["FLO_\(providerToken)_TTS_SPEED"]) ??
                nonEmpty(env["FLO_\(alternateToken)_TTS_SPEED"]) ??
                "1.0"
            ) ?? 1.0

            let transcriptionURL = URL(
                string: env["FLO_\(providerToken)_TRANSCRIPTION_URL"] ??
                    env["FLO_\(alternateToken)_TRANSCRIPTION_URL"] ??
                    "https://generativelanguage.googleapis.com/v1beta/models/\(transcriptionModel):generateContent"
            )!
            let ttsURL = URL(
                string: env["FLO_\(providerToken)_TTS_URL"] ??
                    env["FLO_\(alternateToken)_TTS_URL"] ??
                    "https://generativelanguage.googleapis.com/v1beta/models/\(ttsModel):generateContent"
            )!
            let rewriteURL = URL(
                string: env["FLO_\(providerToken)_REWRITE_URL"] ??
                    env["FLO_\(alternateToken)_REWRITE_URL"] ??
                    "https://generativelanguage.googleapis.com/v1beta/models/\(rewriteModel):generateContent"
            )!

            return ProviderRuntimeConfiguration(
                provider: provider,
                transcriptionURL: transcriptionURL,
                ttsURL: ttsURL,
                rewriteURL: rewriteURL,
                transcriptionModel: transcriptionModel,
                ttsModel: ttsModel,
                rewriteModel: rewriteModel,
                ttsVoice: ttsVoice,
                ttsSpeed: ttsSpeed
            )
        }

        return openAICompatibleRewriteConfiguration(provider: provider, env: env)
    }

    private static func openAICompatibleRewriteConfiguration(
        provider: AIProvider,
        env: [String: String]
    ) -> ProviderRuntimeConfiguration {
        let providerToken = envToken(for: provider)
        let modelKey = "FLO_\(providerToken)_REWRITE_MODEL"
        let baseURLKey = "FLO_\(providerToken)_REWRITE_URL"
        let defaultModel = defaultRewriteModel(for: provider)
        let defaultEndpoint = defaultRewriteEndpoint(for: provider)

        let rewriteModel =
            nonEmpty(env["FLO_REWRITE_MODEL"]) ??
            nonEmpty(env[modelKey]) ??
            defaultModel
        let ttsVoice = nonEmpty(env["FLO_TTS_VOICE"]) ?? "alloy"
        let ttsSpeed = Double(nonEmpty(env["FLO_TTS_SPEED"]) ?? "1.0") ?? 1.0
        let endpoint = nonEmpty(env[baseURLKey]) ?? defaultEndpoint
        let rewriteURL = URL(string: endpoint ?? "https://invalid.local/\(provider.rawValue)/chat/completions")!
        let supportsRewrite = endpoint != nil

        return ProviderRuntimeConfiguration(
            provider: provider,
            transcriptionURL: rewriteURL,
            ttsURL: rewriteURL,
            rewriteURL: rewriteURL,
            transcriptionModel: "unsupported",
            ttsModel: "unsupported",
            rewriteModel: rewriteModel,
            ttsVoice: ttsVoice,
            ttsSpeed: ttsSpeed,
            capabilities: .init(transcription: false, tts: false, rewrite: supportsRewrite)
        )
    }

    private static func primaryCredentialEnvKey(for provider: AIProvider) -> String {
        provider.defaultEnvKeyName
    }

    private static func csvCredentialEnvKey(for provider: AIProvider) -> String {
        provider.defaultEnvKeysName
    }

    private static func legacyCredentialEnvKeys(for provider: AIProvider) -> [String] {
        var keys: [String] = []
        if let entry = ProviderCatalog.entry(for: provider) {
            keys.append(contentsOf: entry.legacyEnvKeys)
        }

        if provider == .openai {
            keys.append("OPENAI_API_KEY")
        } else if provider == .gemini || provider == .google {
            keys.append("GEMINI_API_KEY")
            keys.append("GOOGLE_GENERATIVE_AI_API_KEY")
        }

        return uniquePreservingOrder(keys)
    }

    private static func parseProviders(_ raw: String?) -> [AIProvider] {
        guard let raw else {
            return []
        }

        let parts = raw
            .split { $0 == "," || $0 == ";" || $0 == "|" || $0 == " " || $0 == "\n" || $0 == "\t" }
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

        return parts.compactMap(AIProvider.init(rawValue:))
    }

    private static func parseCredentialPool(csvValue: String?, fallbackValues: [String?]) -> [String] {
        var values: [String] = []

        if let csvValue {
            values.append(contentsOf: csvValue.split(separator: ",").map(String.init))
        }

        values.append(contentsOf: fallbackValues.compactMap { $0 })
        values = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return uniquePreservingOrder(values)
    }

    private static func cleanCredentialPool(_ pool: [AIProvider: [String]]) -> [AIProvider: [String]] {
        var cleaned: [AIProvider: [String]] = [:]
        for provider in AIProvider.allCases {
            let values = (pool[provider] ?? [])
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !values.isEmpty {
                cleaned[provider] = uniquePreservingOrder(values)
            }
        }
        return cleaned
    }

    private static func normalizedProviders(_ providers: [AIProvider]) -> [AIProvider] {
        uniquePreservingOrder(providers)
    }

    private static func uniquePreservingOrder<T: Hashable>(_ values: [T]) -> [T] {
        var seen = Set<T>()
        var result: [T] = []
        for value in values where seen.insert(value).inserted {
            result.append(value)
        }
        return result
    }

    private static func parseBoolean(_ raw: String?, defaultValue: Bool) -> Bool {
        guard let raw else {
            return defaultValue
        }
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            return true
        case "0", "false", "no", "off":
            return false
        default:
            return defaultValue
        }
    }

    private static func nonEmpty(_ raw: String?) -> String? {
        guard let raw else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func envToken(for provider: AIProvider) -> String {
        provider.rawValue.uppercased().map { character in
            if ("A"..."Z").contains(character) || ("0"..."9").contains(character) {
                return character
            }
            return "_"
        }.reduce(into: "") { $0.append($1) }
    }

    private static func defaultRewriteModel(for provider: AIProvider) -> String {
        if provider == .openrouter {
            return "openai/gpt-4o-mini"
        }
        if provider == .groq {
            return "llama-3.3-70b-versatile"
        }
        if provider == .xai {
            return "grok-3-mini"
        }
        if provider == .deepinfra {
            return "meta-llama/Llama-3.3-70B-Instruct"
        }
        if provider == .together || provider == .togetherai {
            return "meta-llama/Llama-3.3-70B-Instruct-Turbo"
        }
        if provider == .perplexity {
            return "sonar"
        }
        return "gpt-4o-mini"
    }

    private static func defaultRewriteEndpoint(for provider: AIProvider) -> String? {
        if provider == .groq {
            return "https://api.groq.com/openai/v1/chat/completions"
        }
        if provider == .xai {
            return "https://api.x.ai/v1/chat/completions"
        }
        if provider == .deepinfra {
            return "https://api.deepinfra.com/v1/openai/chat/completions"
        }
        if provider == .together || provider == .togetherai {
            return "https://api.together.xyz/v1/chat/completions"
        }
        if provider == .perplexity {
            return "https://api.perplexity.ai/chat/completions"
        }

        guard let base = ProviderCatalog.entry(for: provider)?.apiBaseURL?.trimmingCharacters(in: .whitespacesAndNewlines),
            !base.isEmpty
        else {
            return nil
        }

        let normalized = base.lowercased()
        if normalized.contains("chat/completions") {
            return base
        }

        if base.hasSuffix("/") {
            return base + "chat/completions"
        }

        if normalized.hasSuffix("/v1") || normalized.hasSuffix("/openai") || normalized.hasSuffix("/inference") {
            return base + "/chat/completions"
        }

        return base + "/chat/completions"
    }
}
