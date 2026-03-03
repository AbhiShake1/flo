import Foundation
import AppCore

public enum AIProvider: String, Sendable {
    case openai
    case gemini
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
        oauth: OAuthConfiguration?
    ) {
        self.provider = provider
        self.transcriptionURL = transcriptionURL
        self.ttsURL = ttsURL
        self.rewriteURL = rewriteURL
        self.openAIApiKey = openAIApiKey
        self.geminiApiKey = geminiApiKey
        self.transcriptionModel = transcriptionModel
        self.ttsModel = ttsModel
        self.rewriteModel = rewriteModel
        self.ttsVoice = ttsVoice
        self.ttsSpeed = ttsSpeed
        self.maxTTSCharactersPerChunk = maxTTSCharactersPerChunk
        self.retainAudioDebugArtifacts = retainAudioDebugArtifacts
        self.hostAllowlist = hostAllowlist
        self.featureFlags = featureFlags
        self.manualUpdateURL = manualUpdateURL
        self.oauth = oauth
    }

    public var localCredentialToken: String? {
        switch provider {
        case .openai:
            return openAIApiKey
        case .gemini:
            return geminiApiKey
        }
    }

    public var providerDisplayName: String {
        switch provider {
        case .openai:
            return "OpenAI"
        case .gemini:
            return "Gemini"
        }
    }

    public static func loadFromEnvironment(_ env: [String: String] = ProcessInfo.processInfo.environment) -> FloConfiguration {
        let provider = AIProvider(
            rawValue: (env["FLO_AI_PROVIDER"] ?? "openai")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        ) ?? .openai

        let openAIApiKey = nonEmpty(env["FLO_OPENAI_API_KEY"]) ?? nonEmpty(env["OPENAI_API_KEY"])
        let geminiApiKey = nonEmpty(env["FLO_GEMINI_API_KEY"]) ?? nonEmpty(env["GEMINI_API_KEY"])

        let defaultTranscriptionModel: String
        let defaultTTSModel: String
        let defaultRewriteModel: String
        let transcriptionURL: URL
        let ttsURL: URL
        let rewriteURL: URL

        switch provider {
        case .openai:
            defaultTranscriptionModel = "gpt-4o-mini-transcribe"
            defaultTTSModel = "gpt-4o-mini-tts"
            defaultRewriteModel = "gpt-4o-mini"

            transcriptionURL = URL(
                string: env["FLO_OPENAI_TRANSCRIPTION_URL"] ?? "https://api.openai.com/v1/audio/transcriptions"
            )!
            ttsURL = URL(
                string: env["FLO_OPENAI_TTS_URL"] ?? "https://api.openai.com/v1/audio/speech"
            )!
            rewriteURL = URL(
                string: env["FLO_OPENAI_REWRITE_URL"] ?? "https://api.openai.com/v1/chat/completions"
            )!
        case .gemini:
            defaultTranscriptionModel = "gemini-3-flash-preview"
            defaultTTSModel = "gemini-2.5-flash-preview-tts"
            defaultRewriteModel = "gemini-2.0-flash"
            let geminiTranscriptionModel = nonEmpty(env["FLO_TRANSCRIPTION_MODEL"]) ??
                nonEmpty(env["FLO_GEMINI_TRANSCRIPTION_MODEL"]) ??
                defaultTranscriptionModel
            let geminiTTSModel = nonEmpty(env["FLO_TTS_MODEL"]) ??
                nonEmpty(env["FLO_GEMINI_TTS_MODEL"]) ??
                defaultTTSModel
            let geminiRewriteModel = nonEmpty(env["FLO_REWRITE_MODEL"]) ??
                nonEmpty(env["FLO_GEMINI_REWRITE_MODEL"]) ??
                defaultRewriteModel

            transcriptionURL = URL(
                string: env["FLO_GEMINI_TRANSCRIPTION_URL"] ??
                    "https://generativelanguage.googleapis.com/v1beta/models/\(geminiTranscriptionModel):generateContent"
            )!
            ttsURL = URL(
                string: env["FLO_GEMINI_TTS_URL"] ??
                    "https://generativelanguage.googleapis.com/v1beta/models/\(geminiTTSModel):generateContent"
            )!
            rewriteURL = URL(
                string: env["FLO_GEMINI_REWRITE_URL"] ??
                    "https://generativelanguage.googleapis.com/v1beta/models/\(geminiRewriteModel):generateContent"
            )!
        }

        let transcriptionModel = nonEmpty(env["FLO_TRANSCRIPTION_MODEL"]) ?? {
            switch provider {
            case .openai:
                return nonEmpty(env["FLO_OPENAI_TRANSCRIPTION_MODEL"]) ?? "gpt-4o-mini-transcribe"
            case .gemini:
                return nonEmpty(env["FLO_GEMINI_TRANSCRIPTION_MODEL"]) ?? "gemini-3-flash-preview"
            }
        }()
        let ttsModel = nonEmpty(env["FLO_TTS_MODEL"]) ?? {
            switch provider {
            case .openai:
                return nonEmpty(env["FLO_OPENAI_TTS_MODEL"]) ?? "gpt-4o-mini-tts"
            case .gemini:
                return nonEmpty(env["FLO_GEMINI_TTS_MODEL"]) ?? "gemini-2.5-flash-preview-tts"
            }
        }()
        let rewriteModel = nonEmpty(env["FLO_REWRITE_MODEL"]) ?? {
            switch provider {
            case .openai:
                return nonEmpty(env["FLO_OPENAI_REWRITE_MODEL"]) ?? "gpt-4o-mini"
            case .gemini:
                return nonEmpty(env["FLO_GEMINI_REWRITE_MODEL"]) ?? "gemini-2.0-flash"
            }
        }()
        let ttsVoice = nonEmpty(env["FLO_TTS_VOICE"]) ?? {
            switch provider {
            case .openai:
                return nonEmpty(env["FLO_OPENAI_TTS_VOICE"]) ?? "alloy"
            case .gemini:
                return nonEmpty(env["FLO_GEMINI_TTS_VOICE"]) ?? "Kore"
            }
        }()
        let ttsSpeed = Double(
            nonEmpty(env["FLO_TTS_SPEED"]) ??
                nonEmpty(env["FLO_OPENAI_TTS_SPEED"]) ??
                nonEmpty(env["FLO_GEMINI_TTS_SPEED"]) ??
                "1.0"
        ) ?? 1.0
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
        if let host = transcriptionURL.host?.lowercased() {
            hostAllowlist.insert(host)
        }
        if let host = ttsURL.host?.lowercased() {
            hostAllowlist.insert(host)
        }
        if let host = rewriteURL.host?.lowercased() {
            hostAllowlist.insert(host)
        }

        let oauth: OAuthConfiguration?
        let oauthEnabled = parseBoolean(env["FLO_CHATGPT_OAUTH_ENABLED"], defaultValue: provider == .openai)
        if provider == .openai && oauthEnabled {
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

        return FloConfiguration(
            provider: provider,
            transcriptionURL: transcriptionURL,
            ttsURL: ttsURL,
            rewriteURL: rewriteURL,
            openAIApiKey: openAIApiKey,
            geminiApiKey: geminiApiKey,
            transcriptionModel: transcriptionModel,
            ttsModel: ttsModel,
            rewriteModel: rewriteModel,
            ttsVoice: ttsVoice,
            ttsSpeed: ttsSpeed,
            maxTTSCharactersPerChunk: maxTTSCharactersPerChunk,
            retainAudioDebugArtifacts: retainAudioDebugArtifacts,
            hostAllowlist: hostAllowlist,
            featureFlags: featureFlags,
            manualUpdateURL: manualUpdateURL,
            oauth: oauth
        )
    }

    public func isAllowedHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else {
            return false
        }
        return hostAllowlist.contains(host)
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
}
