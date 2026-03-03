import AppCore
import Foundation

private struct ProviderCredentialCandidate: Sendable {
    let provider: AIProvider
    let token: String
}

private enum ProviderOperation: String, Sendable {
    case transcription
    case tts
    case rewrite

    func isSupported(by provider: AIProvider, configuration: FloConfiguration) -> Bool {
        switch self {
        case .transcription:
            return configuration.supportsTranscription(for: provider)
        case .tts:
            return configuration.supportsTTS(for: provider)
        case .rewrite:
            return configuration.supportsRewrite(for: provider)
        }
    }
}

private struct ProviderFailureState: Sendable {
    var consecutiveFailures: Int = 0
    var blockedUntil: Date?
}

private actor ProviderRoutingState {
    private var cursorByProvider: [AIProvider: Int] = [:]
    private var failureStateByProvider: [AIProvider: ProviderFailureState] = [:]

    func rotatedTokens(for provider: AIProvider, tokens: [String]) -> [String] {
        guard !tokens.isEmpty else {
            return []
        }

        let startIndex = cursorByProvider[provider, default: 0] % tokens.count
        cursorByProvider[provider] = (startIndex + 1) % tokens.count

        if startIndex == 0 {
            return tokens
        }

        let prefix = Array(tokens[startIndex..<tokens.count])
        let suffix = Array(tokens[0..<startIndex])
        return prefix + suffix
    }

    func isProviderAvailable(_ provider: AIProvider, now: Date = Date()) -> Bool {
        guard var state = failureStateByProvider[provider] else {
            return true
        }

        if let blockedUntil = state.blockedUntil {
            if blockedUntil > now {
                return false
            }
            state.blockedUntil = nil
            state.consecutiveFailures = 0
            failureStateByProvider[provider] = state
        }

        return true
    }

    func recordSuccess(provider: AIProvider) {
        failureStateByProvider[provider] = ProviderFailureState()
    }

    func recordFailure(provider: AIProvider, policy: ProviderFailoverPolicy, retryable: Bool, now: Date = Date()) {
        guard retryable else {
            return
        }

        var state = failureStateByProvider[provider] ?? ProviderFailureState()
        state.consecutiveFailures += 1

        if state.consecutiveFailures >= policy.failureThreshold {
            let cooldown = TimeInterval(policy.cooldownSeconds)
            state.blockedUntil = now.addingTimeInterval(cooldown)
            state.consecutiveFailures = 0
        }

        failureStateByProvider[provider] = state
    }
}

private func uniqueTokens(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for value in values {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            continue
        }
        if seen.insert(trimmed).inserted {
            result.append(trimmed)
        }
    }
    return result
}

private func effectiveConfiguration(
    for baseConfiguration: FloConfiguration,
    routingStore: ProviderRoutingStore?
) -> FloConfiguration {
    guard let routingStore else {
        return baseConfiguration
    }
    let overrides = routingStore.loadOverrides()
    return baseConfiguration.applyingRoutingOverrides(overrides)
}

private func failoverProviders(for configuration: FloConfiguration, operation: ProviderOperation) -> [AIProvider] {
    let policy = configuration.failoverPolicy

    var providers = configuration.providerOrder
        .filter { operation.isSupported(by: $0, configuration: configuration) }

    if let allowedProviders = policy.allowedProviders {
        providers = providers.filter { allowedProviders.contains($0) }
    }

    if !policy.allowCrossProviderFallback, let first = providers.first {
        providers = [first]
    }

    return providers
}

private func providerCredentialCandidates(
    for configuration: FloConfiguration,
    operation: ProviderOperation,
    preferredToken: String,
    dynamicCredentialPool: [AIProvider: [String]],
    routingState: ProviderRoutingState
) async -> [ProviderCredentialCandidate] {
    var providers = failoverProviders(for: configuration, operation: operation)
    let policy = configuration.failoverPolicy
    let maxAttempts = max(1, policy.maxAttempts)

    // Allow newly added keychain-backed providers to participate immediately.
    for provider in AIProvider.allCases {
        guard operation.isSupported(by: provider, configuration: configuration) else {
            continue
        }
        if let allowedProviders = policy.allowedProviders, !allowedProviders.contains(provider) {
            continue
        }
        if !providers.contains(provider), !(dynamicCredentialPool[provider] ?? []).isEmpty {
            providers.append(provider)
        }
    }

    if !policy.allowCrossProviderFallback, let first = providers.first {
        providers = [first]
    }

    var result: [ProviderCredentialCandidate] = []

    for provider in providers {
        guard await routingState.isProviderAvailable(provider) else {
            continue
        }

        let keychainCredentials = dynamicCredentialPool[provider] ?? []
        var merged = uniqueTokens(keychainCredentials + configuration.credentials(for: provider))

        if provider == configuration.provider {
            merged = uniqueTokens([preferredToken] + merged)
        }

        guard !merged.isEmpty else {
            continue
        }

        let rotated = await routingState.rotatedTokens(for: provider, tokens: merged)
        for token in rotated {
            result.append(ProviderCredentialCandidate(provider: provider, token: token))
            if result.count >= maxAttempts {
                return result
            }
        }
    }

    return result
}

public final class FailoverTranscriptionService: TranscriptionService, @unchecked Sendable {
    private let configuration: FloConfiguration
    private let services: [AIProvider: TranscriptionService]
    private let credentialStore: ProviderCredentialStore?
    private let routingStore: ProviderRoutingStore?
    private let routingState = ProviderRoutingState()

    public init(
        configuration: FloConfiguration,
        services: [AIProvider: TranscriptionService]? = nil,
        urlSession: URLSession = .shared,
        credentialStore: ProviderCredentialStore? = nil,
        routingStore: ProviderRoutingStore? = nil
    ) {
        self.configuration = configuration
        self.credentialStore = credentialStore
        self.routingStore = routingStore
        if let services {
            self.services = services
        } else {
            var built: [AIProvider: TranscriptionService] = [:]
            for provider in AIProvider.allCases where configuration.supportsTranscription(for: provider) {
                if provider == .openai {
                    built[provider] = OpenAITranscriptionService(
                        configuration: configuration.scoped(to: provider),
                        urlSession: urlSession
                    )
                } else {
                    built[provider] = GeminiTranscriptionService(
                        configuration: configuration.scoped(to: provider),
                        urlSession: urlSession
                    )
                }
            }
            self.services = built
        }
    }

    public func transcribe(audioFileURL: URL, authToken: String) async throws -> TranscriptResult {
        let activeConfiguration = effectiveConfiguration(for: configuration, routingStore: routingStore)
        let candidates = await providerCredentialCandidates(
            for: activeConfiguration,
            operation: .transcription,
            preferredToken: authToken,
            dynamicCredentialPool: credentialPoolSnapshot(),
            routingState: routingState
        )

        guard !candidates.isEmpty else {
            throw FloError.unauthorized
        }

        var lastError: Error = FloError.unauthorized
        for candidate in candidates {
            guard let service = services[candidate.provider] else {
                continue
            }

            do {
                let result = try await service.transcribe(audioFileURL: audioFileURL, authToken: candidate.token)
                await routingState.recordSuccess(provider: candidate.provider)
                return result
            } catch {
                let shouldFailover = ProviderFailoverClassifier.shouldFailover(after: error)
                await routingState.recordFailure(
                    provider: candidate.provider,
                    policy: activeConfiguration.failoverPolicy,
                    retryable: shouldFailover
                )
                lastError = error
                if !shouldFailover {
                    throw error
                }
            }
        }

        throw lastError
    }

    private func credentialPoolSnapshot() -> [AIProvider: [String]] {
        guard let credentialStore else {
            return [:]
        }

        var pool: [AIProvider: [String]] = [:]
        for provider in AIProvider.allCases {
            let credentials = credentialStore.credentials(for: provider.rawValue)
            if !credentials.isEmpty {
                pool[provider] = credentials
            }
        }
        return pool
    }
}

@MainActor
public final class FailoverTTSService: TTSService {
    private let configuration: FloConfiguration
    private let services: [AIProvider: TTSService]
    private let credentialStore: ProviderCredentialStore?
    private let routingStore: ProviderRoutingStore?
    private let routingState = ProviderRoutingState()

    public init(
        configuration: FloConfiguration,
        services: [AIProvider: TTSService]? = nil,
        urlSession: URLSession = .shared,
        openAIPlaybackMode: OpenAITTSService.PlaybackMode = .normal,
        geminiPlaybackMode: GeminiTTSService.PlaybackMode = .normal,
        credentialStore: ProviderCredentialStore? = nil,
        routingStore: ProviderRoutingStore? = nil
    ) {
        self.configuration = configuration
        self.credentialStore = credentialStore
        self.routingStore = routingStore
        if let services {
            self.services = services
        } else {
            var built: [AIProvider: TTSService] = [:]
            for provider in AIProvider.allCases where configuration.supportsTTS(for: provider) {
                if provider == .openai {
                    built[provider] = OpenAITTSService(
                        configuration: configuration.scoped(to: provider),
                        urlSession: urlSession,
                        playbackMode: openAIPlaybackMode
                    )
                } else {
                    built[provider] = GeminiTTSService(
                        configuration: configuration.scoped(to: provider),
                        urlSession: urlSession,
                        playbackMode: geminiPlaybackMode
                    )
                }
            }
            self.services = built
        }
    }

    public func synthesizeAndPlay(text: String, authToken: String, voice: String, speed: Double) async throws {
        let activeConfiguration = effectiveConfiguration(for: configuration, routingStore: routingStore)
        let candidates = await providerCredentialCandidates(
            for: activeConfiguration,
            operation: .tts,
            preferredToken: authToken,
            dynamicCredentialPool: credentialPoolSnapshot(),
            routingState: routingState
        )

        guard !candidates.isEmpty else {
            throw FloError.unauthorized
        }

        var lastError: Error = FloError.unauthorized
        for candidate in candidates {
            guard let service = services[candidate.provider] else {
                continue
            }

            do {
                try await service.synthesizeAndPlay(text: text, authToken: candidate.token, voice: voice, speed: speed)
                await routingState.recordSuccess(provider: candidate.provider)
                return
            } catch {
                let shouldFailover = ProviderFailoverClassifier.shouldFailover(after: error)
                await routingState.recordFailure(
                    provider: candidate.provider,
                    policy: activeConfiguration.failoverPolicy,
                    retryable: shouldFailover
                )
                lastError = error
                if !shouldFailover {
                    throw error
                }
            }
        }

        throw lastError
    }

    public func stopPlayback() {
        for service in services.values {
            service.stopPlayback()
        }
    }

    private func credentialPoolSnapshot() -> [AIProvider: [String]] {
        guard let credentialStore else {
            return [:]
        }

        var pool: [AIProvider: [String]] = [:]
        for provider in AIProvider.allCases {
            let credentials = credentialStore.credentials(for: provider.rawValue)
            if !credentials.isEmpty {
                pool[provider] = credentials
            }
        }
        return pool
    }
}

public final class FailoverDictationRewriteService: DictationRewriteService, @unchecked Sendable {
    private let configuration: FloConfiguration
    private let services: [AIProvider: DictationRewriteService]
    private let credentialStore: ProviderCredentialStore?
    private let routingStore: ProviderRoutingStore?
    private let routingState = ProviderRoutingState()

    public init(
        configuration: FloConfiguration,
        services: [AIProvider: DictationRewriteService]? = nil,
        urlSession: URLSession = .shared,
        credentialStore: ProviderCredentialStore? = nil,
        routingStore: ProviderRoutingStore? = nil
    ) {
        self.configuration = configuration
        self.credentialStore = credentialStore
        self.routingStore = routingStore
        if let services {
            self.services = services
        } else {
            var built: [AIProvider: DictationRewriteService] = [:]
            for provider in AIProvider.allCases where configuration.supportsRewrite(for: provider) {
                if provider == .gemini || provider == .google {
                    built[provider] = GeminiDictationRewriteService(
                        configuration: configuration.scoped(to: provider),
                        urlSession: urlSession
                    )
                } else {
                    built[provider] = OpenAIDictationRewriteService(
                        configuration: configuration.scoped(to: provider),
                        urlSession: urlSession
                    )
                }
            }
            self.services = built
        }
    }

    public func rewrite(
        transcript: String,
        authToken: String,
        preferences: DictationRewritePreferences
    ) async throws -> String {
        guard preferences.rewriteEnabled else {
            return transcript
        }

        let activeConfiguration = effectiveConfiguration(for: configuration, routingStore: routingStore)
        let candidates = await providerCredentialCandidates(
            for: activeConfiguration,
            operation: .rewrite,
            preferredToken: authToken,
            dynamicCredentialPool: credentialPoolSnapshot(),
            routingState: routingState
        )

        guard !candidates.isEmpty else {
            return transcript
        }

        var lastError: Error = FloError.unauthorized
        for candidate in candidates {
            guard let service = services[candidate.provider] else {
                continue
            }

            do {
                let rewritten = try await service.rewrite(
                    transcript: transcript,
                    authToken: candidate.token,
                    preferences: preferences
                )
                await routingState.recordSuccess(provider: candidate.provider)
                return rewritten
            } catch {
                let shouldFailover = ProviderFailoverClassifier.shouldFailover(after: error)
                await routingState.recordFailure(
                    provider: candidate.provider,
                    policy: activeConfiguration.failoverPolicy,
                    retryable: shouldFailover
                )
                lastError = error
                if !shouldFailover {
                    throw error
                }
            }
        }

        throw lastError
    }

    private func credentialPoolSnapshot() -> [AIProvider: [String]] {
        guard let credentialStore else {
            return [:]
        }

        var pool: [AIProvider: [String]] = [:]
        for provider in AIProvider.allCases {
            let credentials = credentialStore.credentials(for: provider.rawValue)
            if !credentials.isEmpty {
                pool[provider] = credentials
            }
        }
        return pool
    }
}
