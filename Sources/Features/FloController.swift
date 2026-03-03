import AppCore
import AppKit
import Combine
import Foundation
import Infrastructure

@MainActor
public final class FloController: ObservableObject {
    @Published public private(set) var authState: AuthState = .loggedOut
    @Published public private(set) var recorderState: RecorderState = .idle
    @Published public private(set) var permissionStatus: PermissionStatus
    @Published public private(set) var shortcutBindings: [ShortcutBinding]
    @Published public private(set) var historyEntries: [HistoryEntry]
    @Published public private(set) var latestAudioLevel: Float = 0
    @Published public private(set) var hotkeysEnabled = false
    @Published public private(set) var voicePreferences: VoicePreferences
    @Published public private(set) var dictationRewritePreferences: DictationRewritePreferences
    @Published public private(set) var isVoicePreviewInProgress = false
    @Published public private(set) var onboardingHotkeyConfirmed: Bool
    @Published public private(set) var oauthBlockerMessage: String?
    @Published public private(set) var usesSavedProviderCredential = false
    @Published public private(set) var liveDictationEnabled: Bool
    @Published public private(set) var liveTranscriptPreview: String = ""
    @Published public private(set) var providerRoutingOverrides: ProviderRoutingOverrides
    @Published public private(set) var modelsDevCatalogSnapshot: ModelsDevCatalogSnapshot
    @Published public var statusMessage: String?

    public var isAuthenticated: Bool {
        if case .loggedIn = authState {
            return true
        }
        return false
    }

    public var canAttemptLogin: Bool {
        if hasLocalCredential {
            return false
        }
        if !activeProviderSupportsOAuth {
            return false
        }
        return effectiveConfiguration.oauth != nil && oauthBlockerMessage == nil
    }

    public var authProviderDisplayName: String {
        providerDisplayName(for: effectiveConfiguration.provider)
    }

    public var availableProviders: [AIProvider] {
        var seen = Set<AIProvider>()
        var providers: [AIProvider] = []

        for remoteProvider in modelsDevCatalogSnapshot.providers {
            guard let provider = AIProvider(rawValue: remoteProvider.id), seen.insert(provider).inserted else {
                continue
            }
            providers.append(provider)
        }

        for provider in AIProvider.allCases where seen.insert(provider).inserted {
            providers.append(provider)
        }

        return providers
    }

    public var hasModelsDevCatalog: Bool {
        modelsDevCatalogSnapshot.fetchedAt != .distantPast
    }

    public var configuredProviderOrder: [AIProvider] {
        effectiveProviderOrder
    }

    public var enabledProvidersInFailoverOrder: [AIProvider] {
        let order = effectiveProviderOrder
        guard let allowed = effectiveFailoverPolicy.allowedProviders else {
            return order
        }
        return order.filter { allowed.contains($0) }
    }

    public var activeProviderSupportsOAuth: Bool {
        effectiveConfiguration.provider.supportsOAuth
    }

    public var supportedVoices: [String] {
        VoiceCatalog.supportedVoices(for: voicePreferenceProvider)
    }

    public var featureFlags: FeatureFlags {
        environment.configuration.featureFlags
    }

    public var manualUpdateURL: URL? {
        environment.configuration.manualUpdateURL
    }

    public var lastDictationTranscript: String? {
        guard let entry = historyEntries.first(where: { $0.kind == .dictation && $0.success }) else {
            return nil
        }
        let candidate = (entry.outputText ?? entry.inputText).trimmingCharacters(in: .whitespacesAndNewlines)
        return candidate.isEmpty ? nil : candidate
    }

    public var canPasteLastTranscript: Bool {
        lastDictationTranscript != nil
    }

    public var missingPermissions: [PermissionKind] {
        var missing: [PermissionKind] = []
        if permissionStatus.microphone != .granted {
            missing.append(.microphone)
        }
        if permissionStatus.accessibility != .granted {
            missing.append(.accessibility)
        }
        if permissionStatus.inputMonitoring != .granted {
            missing.append(.inputMonitoring)
        }
        return missing
    }

    public var requiresOnboardingChecklist: Bool {
        !onboardingHotkeyConfirmed || !missingPermissions.isEmpty
    }

    public var canManageProviderCredentialInApp: Bool {
        true
    }

    public var providerCredentialSourceLabel: String? {
        providerCredentialSourceLabel(for: effectiveConfiguration.provider)
    }

    public var canRemoveSavedProviderCredential: Bool {
        canRemoveSavedProviderCredential(for: effectiveConfiguration.provider)
    }

    public var failoverAllowCrossProviderFallback: Bool {
        effectiveFailoverPolicy.allowCrossProviderFallback
    }

    public var failoverMaxAttempts: Int {
        effectiveFailoverPolicy.maxAttempts
    }

    public var failoverFailureThreshold: Int {
        effectiveFailoverPolicy.failureThreshold
    }

    public var failoverCooldownSeconds: Int {
        effectiveFailoverPolicy.cooldownSeconds
    }

    public func providerDisplayName(for provider: AIProvider) -> String {
        modelsDevProviderEntry(for: provider)?.name ?? provider.displayName
    }

    public func providerLogoURL(for provider: AIProvider) -> URL? {
        if let logoURL = modelsDevProviderEntry(for: provider)?.logoURL {
            return logoURL
        }

        guard let encodedProviderID = provider.rawValue.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        return URL(string: "https://models.dev/logos/\(encodedProviderID).svg")
    }

    public func providerModels(for provider: AIProvider, matching query: String = "") -> [ModelsDevModelEntry] {
        var models = modelsDevProviderEntry(for: provider)?.models ?? []
        let activeModel = activeRewriteModel(for: provider)
        if !activeModel.isEmpty, !models.contains(where: { $0.id == activeModel }) {
            models.insert(
                ModelsDevModelEntry(id: activeModel, name: activeModel),
                at: 0
            )
        }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedQuery.isEmpty else {
            return models
        }

        let terms = trimmedQuery.split(separator: " ").map(String.init)
        guard !terms.isEmpty else {
            return models
        }

        return models.filter { model in
            let searchable = "\(model.name) \(model.id)".lowercased()
            return terms.allSatisfy { searchable.contains($0) }
        }
    }

    public func activeRewriteModel(for provider: AIProvider) -> String {
        effectiveConfiguration.runtimeConfiguration(for: provider)?.rewriteModel ?? ""
    }

    public func rewriteModelOverride(for provider: AIProvider) -> String? {
        providerRoutingOverrides.rewriteModelsByProvider?[provider.rawValue]
    }

    public func rewriteModelOverride(for provider: AIProvider, credentialIndex: Int) -> String? {
        guard credentialIndex >= 0 else {
            return nil
        }
        return credentialRewriteModelOverrides(for: provider)[credentialIndex]
    }

    public func activeRewriteModel(for provider: AIProvider, credentialIndex: Int) -> String {
        rewriteModelOverride(for: provider, credentialIndex: credentialIndex) ?? activeRewriteModel(for: provider)
    }

    public func setRewriteModel(_ modelID: String, for provider: AIProvider) {
        let trimmedModelID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModelID.isEmpty else {
            return
        }

        persistRoutingOverrides(
            updating: { current in
                var overrides = current.rewriteModelsByProvider ?? [:]
                overrides[provider.rawValue] = trimmedModelID

                return ProviderRoutingOverrides(
                    providerOrder: current.providerOrder,
                    allowCrossProviderFallback: current.allowCrossProviderFallback,
                    maxAttempts: current.maxAttempts,
                    failureThreshold: current.failureThreshold,
                    cooldownSeconds: current.cooldownSeconds,
                    allowedProviders: current.allowedProviders,
                    rewriteModelsByProvider: overrides,
                    rewriteModelsByProviderCredentialIndex: current.rewriteModelsByProviderCredentialIndex
                )
            },
            statusMessage: "\(providerDisplayName(for: provider)) rewrite model set to \(trimmedModelID)."
        )
    }

    public func clearRewriteModelOverride(for provider: AIProvider) {
        persistRoutingOverrides(
            updating: { current in
                var overrides = current.rewriteModelsByProvider ?? [:]
                overrides.removeValue(forKey: provider.rawValue)
                let normalized = overrides.isEmpty ? nil : overrides

                return ProviderRoutingOverrides(
                    providerOrder: current.providerOrder,
                    allowCrossProviderFallback: current.allowCrossProviderFallback,
                    maxAttempts: current.maxAttempts,
                    failureThreshold: current.failureThreshold,
                    cooldownSeconds: current.cooldownSeconds,
                    allowedProviders: current.allowedProviders,
                    rewriteModelsByProvider: normalized,
                    rewriteModelsByProviderCredentialIndex: current.rewriteModelsByProviderCredentialIndex
                )
            },
            statusMessage: "\(providerDisplayName(for: provider)) rewrite model override cleared."
        )
    }

    public func setRewriteModel(_ modelID: String, for provider: AIProvider, credentialIndex: Int) {
        guard credentialIndex >= 0 else {
            return
        }

        let trimmedModelID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModelID.isEmpty else {
            return
        }

        persistRoutingOverrides(
            updating: { current in
                var providerMap = current.rewriteModelsByProviderCredentialIndex ?? [:]
                var indexMap = providerMap[provider.rawValue] ?? [:]
                indexMap[String(credentialIndex)] = trimmedModelID
                providerMap[provider.rawValue] = indexMap

                return ProviderRoutingOverrides(
                    providerOrder: current.providerOrder,
                    allowCrossProviderFallback: current.allowCrossProviderFallback,
                    maxAttempts: current.maxAttempts,
                    failureThreshold: current.failureThreshold,
                    cooldownSeconds: current.cooldownSeconds,
                    allowedProviders: current.allowedProviders,
                    rewriteModelsByProvider: current.rewriteModelsByProvider,
                    rewriteModelsByProviderCredentialIndex: providerMap
                )
            },
            statusMessage: "\(providerDisplayName(for: provider)) key \(credentialIndex + 1) model set to \(trimmedModelID)."
        )
    }

    public func clearRewriteModelOverride(for provider: AIProvider, credentialIndex: Int) {
        guard credentialIndex >= 0 else {
            return
        }

        persistRoutingOverrides(
            updating: { current in
                var providerMap = current.rewriteModelsByProviderCredentialIndex ?? [:]
                var indexMap = providerMap[provider.rawValue] ?? [:]
                indexMap.removeValue(forKey: String(credentialIndex))
                if indexMap.isEmpty {
                    providerMap.removeValue(forKey: provider.rawValue)
                } else {
                    providerMap[provider.rawValue] = indexMap
                }
                let normalized = providerMap.isEmpty ? nil : providerMap

                return ProviderRoutingOverrides(
                    providerOrder: current.providerOrder,
                    allowCrossProviderFallback: current.allowCrossProviderFallback,
                    maxAttempts: current.maxAttempts,
                    failureThreshold: current.failureThreshold,
                    cooldownSeconds: current.cooldownSeconds,
                    allowedProviders: current.allowedProviders,
                    rewriteModelsByProvider: current.rewriteModelsByProvider,
                    rewriteModelsByProviderCredentialIndex: normalized
                )
            },
            statusMessage: "\(providerDisplayName(for: provider)) key \(credentialIndex + 1) model override cleared."
        )
    }

    public func refreshModelsDevCatalog(forceRefresh: Bool = false) async {
        let snapshot = await modelsDevCatalogService.loadCatalog(forceRefresh: forceRefresh)
        modelsDevCatalogSnapshot = snapshot
    }

    public func providerSupportsOAuth(_ provider: AIProvider) -> Bool {
        provider.supportsOAuth
    }

    public func providerCredentialSourceLabel(for provider: AIProvider) -> String? {
        let savedCount = savedCredentialTokens(for: provider).count
        if savedCount > 0 {
            if savedCount == 1 {
                return "Saved in app keychain"
            }
            return "Saved in app keychain (\(savedCount) keys)"
        }

        return nil
    }

    public func canRemoveSavedProviderCredential(for provider: AIProvider) -> Bool {
        !savedCredentialTokens(for: provider).isEmpty
    }

    public func configuredKeyCount(for provider: AIProvider) -> Int {
        mergedCredentialTokens(for: provider).count
    }

    public func providerCredentials(for provider: AIProvider) -> [String] {
        savedCredentialTokens(for: provider)
    }

    @discardableResult
    public func copyProviderCredential(at index: Int, for provider: AIProvider) -> Bool {
        let credentials = savedCredentialTokens(for: provider)
        guard credentials.indices.contains(index) else {
            statusMessage = "Could not copy API key."
            return false
        }

        let copied = copyToClipboard(credentials[index])
        statusMessage = copied
            ? "\(provider.displayName) API key copied to clipboard."
            : "Could not copy API key."
        return copied
    }

    public func addProviderCredential(_ credential: String, for provider: AIProvider) {
        let additions = parseCredentialInput(credential)
        guard !additions.isEmpty else {
            statusMessage = "API key is empty."
            return
        }

        let existing = savedCredentialTokens(for: provider)
        let inheritedDefaultModel: String? = existing.isEmpty
            ? nil
            : activeRewriteModel(for: provider, credentialIndex: 0)
        let merged = normalizeCredentialPool(existing + additions)
        saveProviderCredentialPool(
            merged,
            for: provider,
            successMessage: "\(provider.displayName) API key added. Saved keys: \(merged.count).",
            defaultModelForNewCredentials: inheritedDefaultModel
        )
    }

    public func updateProviderCredential(_ credential: String, at index: Int, for provider: AIProvider) {
        let replacements = parseCredentialInput(credential)
        guard let replacement = replacements.first else {
            statusMessage = "API key is empty."
            return
        }

        var existing = savedCredentialTokens(for: provider)
        guard existing.indices.contains(index) else {
            statusMessage = "Could not update API key."
            return
        }

        existing[index] = replacement
        saveProviderCredentialPool(
            existing,
            for: provider,
            successMessage: "\(provider.displayName) API key updated."
        )
    }

    public func removeProviderCredential(at index: Int, for provider: AIProvider) async {
        var existing = savedCredentialTokens(for: provider)
        guard existing.indices.contains(index) else {
            statusMessage = "Could not remove API key."
            return
        }

        existing.remove(at: index)
        if existing.isEmpty {
            await removeSavedProviderCredential(for: provider)
            return
        }

        saveProviderCredentialPool(
            existing,
            for: provider,
            successMessage: "\(provider.displayName) API key removed. Saved keys: \(existing.count)."
        )
    }

    public func providerSupportsFailoverOperation(_ provider: AIProvider) -> Bool {
        effectiveConfiguration.supportsTranscription(for: provider)
            || effectiveConfiguration.supportsTTS(for: provider)
            || effectiveConfiguration.supportsRewrite(for: provider)
    }

    public func providerEnabledForFailover(_ provider: AIProvider) -> Bool {
        guard effectiveProviderOrder.contains(provider) else {
            return false
        }
        guard let allowed = effectiveFailoverPolicy.allowedProviders else {
            return true
        }
        return allowed.contains(provider)
    }

    public func canMoveProviderUpInFailoverOrder(_ provider: AIProvider) -> Bool {
        guard let index = effectiveProviderOrder.firstIndex(of: provider) else {
            return false
        }
        return index > 0
    }

    public func canMoveProviderDownInFailoverOrder(_ provider: AIProvider) -> Bool {
        guard let index = effectiveProviderOrder.firstIndex(of: provider) else {
            return false
        }
        return index < effectiveProviderOrder.count - 1
    }

    public func moveProviderUpInFailoverOrder(_ provider: AIProvider) {
        moveProviderInFailoverOrder(provider, direction: -1)
    }

    public func moveProviderDownInFailoverOrder(_ provider: AIProvider) {
        moveProviderInFailoverOrder(provider, direction: 1)
    }

    public func reorderProvidersInFailoverOrder(_ providers: [AIProvider]) {
        var seen = Set<AIProvider>()
        let normalized = providers.filter { seen.insert($0).inserted }
        guard !normalized.isEmpty else {
            return
        }

        var reordered = normalized
        for provider in effectiveProviderOrder where !seen.contains(provider) {
            reordered.append(provider)
        }

        persistRoutingOverrides(
            updating: { current in
                ProviderRoutingOverrides(
                    providerOrder: reordered.map(\.rawValue),
                    allowCrossProviderFallback: current.allowCrossProviderFallback,
                    maxAttempts: current.maxAttempts,
                    failureThreshold: current.failureThreshold,
                    cooldownSeconds: current.cooldownSeconds,
                    allowedProviders: current.allowedProviders,
                    rewriteModelsByProvider: current.rewriteModelsByProvider,
                    rewriteModelsByProviderCredentialIndex: current.rewriteModelsByProviderCredentialIndex
                )
            },
            statusMessage: "Updated provider failover order."
        )
    }

    public func addProviderToFailoverOrder(_ provider: AIProvider) {
        setProviderEnabledInFailover(provider, enabled: true)
    }

    public func removeProviderFromFailoverOrder(_ provider: AIProvider) {
        var order = effectiveProviderOrder.filter { $0 != provider }
        if order.isEmpty {
            order = [effectiveConfiguration.provider]
        }

        var allowed = effectiveFailoverPolicy.allowedProviders ?? Set(effectiveProviderOrder)
        allowed.remove(provider)
        if allowed.isEmpty, let fallback = order.first {
            allowed.insert(fallback)
        }

        persistRoutingOverrides(
            updating: { current in
                ProviderRoutingOverrides(
                    providerOrder: order.map(\.rawValue),
                    allowCrossProviderFallback: current.allowCrossProviderFallback,
                    maxAttempts: current.maxAttempts,
                    failureThreshold: current.failureThreshold,
                    cooldownSeconds: current.cooldownSeconds,
                    allowedProviders: Array(allowed).map(\.rawValue).sorted(),
                    rewriteModelsByProvider: current.rewriteModelsByProvider,
                    rewriteModelsByProviderCredentialIndex: current.rewriteModelsByProviderCredentialIndex
                )
            },
            statusMessage: "\(provider.displayName) removed from failover rotation."
        )
    }

    public func setProviderEnabledInFailover(_ provider: AIProvider, enabled: Bool) {
        var order = effectiveProviderOrder
        if !order.contains(provider) {
            order.append(provider)
        }

        var allowed = effectiveFailoverPolicy.allowedProviders ?? Set(order)
        if enabled {
            allowed.insert(provider)
        } else {
            allowed.remove(provider)
            if allowed.isEmpty, let primary = order.first {
                allowed.insert(primary)
            }
        }

        persistRoutingOverrides(
            updating: { current in
                ProviderRoutingOverrides(
                    providerOrder: order.map(\.rawValue),
                    allowCrossProviderFallback: current.allowCrossProviderFallback,
                    maxAttempts: current.maxAttempts,
                    failureThreshold: current.failureThreshold,
                    cooldownSeconds: current.cooldownSeconds,
                    allowedProviders: Array(allowed).map(\.rawValue).sorted(),
                    rewriteModelsByProvider: current.rewriteModelsByProvider,
                    rewriteModelsByProviderCredentialIndex: current.rewriteModelsByProviderCredentialIndex
                )
            },
            statusMessage: enabled
                ? "\(provider.displayName) enabled in failover rotation."
                : "\(provider.displayName) disabled in failover rotation."
        )
    }

    public func setFailoverAllowCrossProviderFallback(_ enabled: Bool) {
        persistRoutingOverrides(
            updating: { current in
                ProviderRoutingOverrides(
                    providerOrder: current.providerOrder,
                    allowCrossProviderFallback: enabled,
                    maxAttempts: current.maxAttempts,
                    failureThreshold: current.failureThreshold,
                    cooldownSeconds: current.cooldownSeconds,
                    allowedProviders: current.allowedProviders,
                    rewriteModelsByProvider: current.rewriteModelsByProvider,
                    rewriteModelsByProviderCredentialIndex: current.rewriteModelsByProviderCredentialIndex
                )
            },
            statusMessage: enabled
                ? "Cross-provider failover enabled."
                : "Cross-provider failover disabled."
        )
    }

    public func setFailoverMaxAttempts(_ value: Int) {
        let clamped = max(1, min(Self.maxFailoverAttempts, value))
        persistRoutingOverrides(
            updating: { current in
                ProviderRoutingOverrides(
                    providerOrder: current.providerOrder,
                    allowCrossProviderFallback: current.allowCrossProviderFallback,
                    maxAttempts: clamped,
                    failureThreshold: current.failureThreshold,
                    cooldownSeconds: current.cooldownSeconds,
                    allowedProviders: current.allowedProviders,
                    rewriteModelsByProvider: current.rewriteModelsByProvider,
                    rewriteModelsByProviderCredentialIndex: current.rewriteModelsByProviderCredentialIndex
                )
            },
            statusMessage: "Failover max attempts set to \(clamped)."
        )
    }

    public func setFailoverFailureThreshold(_ value: Int) {
        let clamped = max(1, min(Self.maxFailoverFailureThreshold, value))
        persistRoutingOverrides(
            updating: { current in
                ProviderRoutingOverrides(
                    providerOrder: current.providerOrder,
                    allowCrossProviderFallback: current.allowCrossProviderFallback,
                    maxAttempts: current.maxAttempts,
                    failureThreshold: clamped,
                    cooldownSeconds: current.cooldownSeconds,
                    allowedProviders: current.allowedProviders,
                    rewriteModelsByProvider: current.rewriteModelsByProvider,
                    rewriteModelsByProviderCredentialIndex: current.rewriteModelsByProviderCredentialIndex
                )
            },
            statusMessage: "Provider failure threshold set to \(clamped)."
        )
    }

    public func setFailoverCooldownSeconds(_ value: Int) {
        let clamped = max(0, min(Self.maxFailoverCooldownSeconds, value))
        persistRoutingOverrides(
            updating: { current in
                ProviderRoutingOverrides(
                    providerOrder: current.providerOrder,
                    allowCrossProviderFallback: current.allowCrossProviderFallback,
                    maxAttempts: current.maxAttempts,
                    failureThreshold: current.failureThreshold,
                    cooldownSeconds: clamped,
                    allowedProviders: current.allowedProviders,
                    rewriteModelsByProvider: current.rewriteModelsByProvider,
                    rewriteModelsByProviderCredentialIndex: current.rewriteModelsByProviderCredentialIndex
                )
            },
            statusMessage: "Provider cooldown set to \(clamped)s."
        )
    }

    private func moveProviderInFailoverOrder(_ provider: AIProvider, direction: Int) {
        guard direction == -1 || direction == 1 else {
            return
        }

        var order = effectiveProviderOrder
        guard let index = order.firstIndex(of: provider) else {
            return
        }

        let targetIndex = index + direction
        guard order.indices.contains(targetIndex) else {
            return
        }

        order.swapAt(index, targetIndex)
        persistRoutingOverrides(
            updating: { current in
                ProviderRoutingOverrides(
                    providerOrder: order.map(\.rawValue),
                    allowCrossProviderFallback: current.allowCrossProviderFallback,
                    maxAttempts: current.maxAttempts,
                    failureThreshold: current.failureThreshold,
                    cooldownSeconds: current.cooldownSeconds,
                    allowedProviders: current.allowedProviders,
                    rewriteModelsByProvider: current.rewriteModelsByProvider,
                    rewriteModelsByProviderCredentialIndex: current.rewriteModelsByProviderCredentialIndex
                )
            },
            statusMessage: "Moved \(provider.displayName) in failover order."
        )
    }

    private func includeProviderInFailoverRotation(_ provider: AIProvider) {
        var order = effectiveProviderOrder
        if !order.contains(provider) {
            order.append(provider)
        }

        var allowed = effectiveFailoverPolicy.allowedProviders ?? Set(order)
        allowed.insert(provider)

        persistRoutingOverrides(
            updating: { current in
                ProviderRoutingOverrides(
                    providerOrder: order.map(\.rawValue),
                    allowCrossProviderFallback: current.allowCrossProviderFallback,
                    maxAttempts: current.maxAttempts,
                    failureThreshold: current.failureThreshold,
                    cooldownSeconds: current.cooldownSeconds,
                    allowedProviders: Array(allowed).map(\.rawValue).sorted(),
                    rewriteModelsByProvider: current.rewriteModelsByProvider,
                    rewriteModelsByProviderCredentialIndex: current.rewriteModelsByProviderCredentialIndex
                )
            },
            statusMessage: nil
        )
    }

    private let environment: AppEnvironment
    private let modelsDevCatalogService: ModelsDevCatalogService
    private var isDictationListening = false
    private var stateResetTask: Task<Void, Never>?
    private var liveInjectedTranscript = ""
    private var didPauseLiveTypingAfterError = false
    private var lastLiveInjectionAt = Date.distantPast
    private static let liveDictationUserDefaultsKey = "flo.live_dictation_enabled"
    private static let maxFailoverAttempts = 20
    private static let maxFailoverFailureThreshold = 10
    private static let maxFailoverCooldownSeconds = 900

    private var effectiveConfiguration: FloConfiguration {
        environment.configuration.applyingRoutingOverrides(providerRoutingOverrides)
    }

    private var effectiveFailoverPolicy: ProviderFailoverPolicy {
        effectiveConfiguration.failoverPolicy
    }

    private func parsedOverrideProviders(from ids: [String]) -> [AIProvider] {
        var seen = Set<AIProvider>()
        var providers: [AIProvider] = []
        for id in ids {
            guard let provider = AIProvider(rawValue: id), seen.insert(provider).inserted else {
                continue
            }
            providers.append(provider)
        }
        return providers
    }

    private func sanitizedRoutingOverrides(_ overrides: ProviderRoutingOverrides) -> ProviderRoutingOverrides {
        let normalizedOrder = parsedOverrideProviders(from: overrides.providerOrder)
        let normalizedAllowedProviders: [String]? = {
            guard let raw = overrides.allowedProviders else {
                return nil
            }
            let parsed = parsedOverrideProviders(from: raw)
            if parsed.isEmpty {
                return nil
            }
            return parsed.map(\.rawValue).sorted()
        }()
        let normalizedRewriteModelsByProvider: [String: String]? = {
            guard let raw = overrides.rewriteModelsByProvider else {
                return nil
            }
            var normalized: [String: String] = [:]
            for (providerID, modelID) in raw {
                guard
                    let provider = AIProvider(rawValue: providerID),
                    !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else {
                    continue
                }
                normalized[provider.rawValue] = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return normalized.isEmpty ? nil : normalized
        }()
        let normalizedRewriteModelsByProviderCredentialIndex: [String: [String: String]]? = {
            guard let raw = overrides.rewriteModelsByProviderCredentialIndex else {
                return nil
            }

            var normalizedByProvider: [String: [String: String]] = [:]
            for (providerID, indexMap) in raw {
                guard let provider = AIProvider(rawValue: providerID) else {
                    continue
                }

                var normalizedByIndex: [String: String] = [:]
                for (indexKey, modelID) in indexMap {
                    guard
                        let index = Int(indexKey),
                        index >= 0,
                        !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    else {
                        continue
                    }
                    normalizedByIndex[String(index)] = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
                }

                if !normalizedByIndex.isEmpty {
                    normalizedByProvider[provider.rawValue] = normalizedByIndex
                }
            }

            return normalizedByProvider.isEmpty ? nil : normalizedByProvider
        }()

        let maxAttempts = overrides.maxAttempts.map { max(1, min(Self.maxFailoverAttempts, $0)) }
        let failureThreshold = overrides.failureThreshold.map { max(1, min(Self.maxFailoverFailureThreshold, $0)) }
        let cooldownSeconds = overrides.cooldownSeconds.map { max(0, min(Self.maxFailoverCooldownSeconds, $0)) }

        return ProviderRoutingOverrides(
            providerOrder: normalizedOrder.map(\.rawValue),
            allowCrossProviderFallback: overrides.allowCrossProviderFallback,
            maxAttempts: maxAttempts,
            failureThreshold: failureThreshold,
            cooldownSeconds: cooldownSeconds,
            allowedProviders: normalizedAllowedProviders,
            rewriteModelsByProvider: normalizedRewriteModelsByProvider,
            rewriteModelsByProviderCredentialIndex: normalizedRewriteModelsByProviderCredentialIndex
        )
    }

    private func persistRoutingOverrides(
        updating transform: (ProviderRoutingOverrides) -> ProviderRoutingOverrides,
        statusMessage: String?
    ) {
        let next = sanitizedRoutingOverrides(transform(providerRoutingOverrides))
        providerRoutingOverrides = next
        environment.providerRoutingStore.saveOverrides(next)
        if let statusMessage {
            self.statusMessage = statusMessage
        }
        environment.logger.info("Updated provider routing overrides.")
    }

    private func savedCredentialTokens(for provider: AIProvider) -> [String] {
        environment.providerCredentialStore
            .credentials(for: provider.rawValue)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var savedCredentialTokens: [String] {
        savedCredentialTokens(for: effectiveConfiguration.provider)
    }

    private var savedCredentialToken: String? {
        savedCredentialTokens.first
    }

    private func credentialRewriteModelOverrides(for provider: AIProvider) -> [Int: String] {
        guard let raw = providerRoutingOverrides.rewriteModelsByProviderCredentialIndex?[provider.rawValue] else {
            return [:]
        }

        var normalized: [Int: String] = [:]
        for (indexKey, modelID) in raw {
            guard
                let index = Int(indexKey),
                index >= 0,
                !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                continue
            }
            normalized[index] = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return normalized
    }

    private func clearCredentialModelOverrides(for provider: AIProvider) {
        persistRoutingOverrides(
            updating: { current in
                var providerMap = current.rewriteModelsByProviderCredentialIndex ?? [:]
                providerMap.removeValue(forKey: provider.rawValue)
                let normalized = providerMap.isEmpty ? nil : providerMap

                return ProviderRoutingOverrides(
                    providerOrder: current.providerOrder,
                    allowCrossProviderFallback: current.allowCrossProviderFallback,
                    maxAttempts: current.maxAttempts,
                    failureThreshold: current.failureThreshold,
                    cooldownSeconds: current.cooldownSeconds,
                    allowedProviders: current.allowedProviders,
                    rewriteModelsByProvider: current.rewriteModelsByProvider,
                    rewriteModelsByProviderCredentialIndex: normalized
                )
            },
            statusMessage: nil
        )
    }

    private func syncCredentialModelOverridesAfterCredentialSave(
        for provider: AIProvider,
        previousCredentials: [String],
        newCredentials: [String],
        previousModelOverrides: [Int: String],
        defaultModelForNewCredentials: String?
    ) {
        var consumedPreviousIndices = Set<Int>()
        var nextByIndex: [String: String] = [:]
        let trimmedDefaultModel = defaultModelForNewCredentials?.trimmingCharacters(in: .whitespacesAndNewlines)

        for (newIndex, token) in newCredentials.enumerated() {
            var matchedPreviousIndex: Int?
            if previousCredentials.indices.contains(newIndex), previousCredentials[newIndex] == token {
                matchedPreviousIndex = newIndex
            } else if let firstMatching = previousCredentials.enumerated().first(
                where: { !consumedPreviousIndices.contains($0.offset) && $0.element == token }
            ) {
                matchedPreviousIndex = firstMatching.offset
            }

            if let matchedPreviousIndex {
                consumedPreviousIndices.insert(matchedPreviousIndex)
                if let existingModel = previousModelOverrides[matchedPreviousIndex] {
                    nextByIndex[String(newIndex)] = existingModel
                }
                continue
            }

            if let trimmedDefaultModel, !trimmedDefaultModel.isEmpty {
                nextByIndex[String(newIndex)] = trimmedDefaultModel
            }
        }

        let currentRawByProvider = providerRoutingOverrides.rewriteModelsByProviderCredentialIndex ?? [:]
        let currentRawForProvider = currentRawByProvider[provider.rawValue] ?? [:]
        if currentRawForProvider == nextByIndex {
            return
        }

        persistRoutingOverrides(
            updating: { current in
                var providerMap = current.rewriteModelsByProviderCredentialIndex ?? [:]
                if nextByIndex.isEmpty {
                    providerMap.removeValue(forKey: provider.rawValue)
                } else {
                    providerMap[provider.rawValue] = nextByIndex
                }
                let normalized = providerMap.isEmpty ? nil : providerMap

                return ProviderRoutingOverrides(
                    providerOrder: current.providerOrder,
                    allowCrossProviderFallback: current.allowCrossProviderFallback,
                    maxAttempts: current.maxAttempts,
                    failureThreshold: current.failureThreshold,
                    cooldownSeconds: current.cooldownSeconds,
                    allowedProviders: current.allowedProviders,
                    rewriteModelsByProvider: current.rewriteModelsByProvider,
                    rewriteModelsByProviderCredentialIndex: normalized
                )
            },
            statusMessage: nil
        )
    }

    private func mergedCredentialTokens(for provider: AIProvider) -> [String] {
        let merged = savedCredentialTokens(for: provider)
        var seen = Set<String>()
        var ordered: [String] = []
        for token in merged where seen.insert(token).inserted {
            ordered.append(token)
        }
        return ordered
    }

    private var localCredentialToken: String? {
        if let token = savedCredentialToken {
            return token
        }

        for provider in effectiveProviderOrder {
            if let token = mergedCredentialTokens(for: provider).first {
                return token
            }
        }
        return nil
    }

    private var effectiveProviderOrder: [AIProvider] {
        var order = effectiveConfiguration.providerOrder
        for provider in AIProvider.allCases where !mergedCredentialTokens(for: provider).isEmpty {
            if !order.contains(provider) {
                order.append(provider)
            }
        }
        if order.isEmpty {
            return [effectiveConfiguration.provider]
        }
        return order
    }

    private var voicePreferenceProvider: AIProvider {
        if let firstTTSProvider = effectiveProviderOrder.first(
            where: { effectiveConfiguration.supportsTTS(for: $0) }
        ) {
            return firstTTSProvider
        }
        return effectiveConfiguration.provider
    }

    private var hasLocalCredential: Bool {
        localCredentialToken != nil
    }

    private var hasAnySavedProviderCredential: Bool {
        for provider in AIProvider.allCases where !savedCredentialTokens(for: provider).isEmpty {
            return true
        }
        return false
    }

    private func modelsDevProviderEntry(for provider: AIProvider) -> ModelsDevProviderEntry? {
        let providerByID = modelsDevCatalogSnapshot.providerByID
        if let direct = providerByID[provider.rawValue] {
            return direct
        }
        if let alias = Self.modelsDevProviderAliasByProviderID[provider.rawValue] {
            return providerByID[alias]
        }
        return nil
    }

    private static let modelsDevProviderAliasByProviderID: [String: String] = [
        "gemini": "google",
        "together": "togetherai"
    ]

    public init(
        environment: AppEnvironment,
        modelsDevCatalogService: ModelsDevCatalogService = .shared
    ) {
        self.environment = environment
        self.modelsDevCatalogService = modelsDevCatalogService

        let loadedBindings = environment.shortcutStore.loadBindings()
        self.shortcutBindings = Self.normalizedBindings(loadedBindings)
        self.permissionStatus = environment.permissionsService.refreshStatus()
        self.historyEntries = (try? environment.historyStore.load()) ?? []
        self.voicePreferences = environment.voicePreferencesStore.load()
        self.dictationRewritePreferences = environment.dictationRewritePreferencesStore.load()
        self.providerRoutingOverrides = environment.providerRoutingStore.loadOverrides()
        self.modelsDevCatalogSnapshot = .empty
        self.onboardingHotkeyConfirmed = environment.onboardingStateStore.hasCompletedHotkeyConfirmation()
        self.liveDictationEnabled = UserDefaults.standard.object(forKey: Self.liveDictationUserDefaultsKey) as? Bool ?? false
        if self.liveDictationEnabled != self.dictationRewritePreferences.liveTypingEnabled {
            var synced = self.dictationRewritePreferences
            synced = DictationRewritePreferences(
                rewriteEnabled: synced.rewriteEnabled,
                liveTypingEnabled: self.liveDictationEnabled,
                liveFinalizationMode: synced.liveFinalizationMode,
                baseTone: synced.baseTone,
                warmth: synced.warmth,
                enthusiasm: synced.enthusiasm,
                headersAndLists: synced.headersAndLists,
                emoji: synced.emoji,
                customInstructions: synced.customInstructions
            )
            self.dictationRewritePreferences = synced
            environment.dictationRewritePreferencesStore.save(synced)
        }
    }

    public func bootstrap() async {
        Task {
            await self.refreshModelsDevCatalog()
        }

        providerRoutingOverrides = environment.providerRoutingStore.loadOverrides()
        configureFloatingBarActions()
        refreshPermissions()
        configureHotkeysIfAllowed()
        usesSavedProviderCredential = hasAnySavedProviderCredential

        if hasLocalCredential {
            let keySession = UserSession(
                accessToken: localCredentialToken ?? "",
                refreshToken: nil,
                tokenType: "Bearer",
                expiresAt: .distantFuture
            )
            authState = .loggedIn(keySession)
            statusMessage = "Using API key mode with provider failover."
            oauthBlockerMessage = nil
            environment.logger.info(
                "Running in API key mode from \(providerCredentialSourceLabel ?? "configured credentials")."
            )
            setRecorderState(.idle)
            voicePreferences = environment.voicePreferencesStore.load()
            dictationRewritePreferences = environment.dictationRewritePreferencesStore.load()
            onboardingHotkeyConfirmed = environment.onboardingStateStore.hasCompletedHotkeyConfirmation()
            historyEntries = (try? environment.historyStore.load()) ?? []
            return
        }

        if !activeProviderSupportsOAuth {
            let blocker = "No API keys found for \(authProviderDisplayName). Add a key in Provider Workbench."
            oauthBlockerMessage = blocker
            authState = .authError(blocker)
            statusMessage = blocker
            environment.logger.error(blocker)
            environment.floatingBarManager.hide()
            historyEntries = (try? environment.historyStore.load()) ?? []
            return
        }

        if effectiveConfiguration.oauth == nil {
            let blocker = "No OAuth provider available and no API keys found. Add a key in Provider Workbench."
            oauthBlockerMessage = blocker
            authState = .authError(blocker)
            statusMessage = blocker
            environment.logger.error(blocker)
            environment.floatingBarManager.hide()
            historyEntries = (try? environment.historyStore.load()) ?? []
            return
        }

        oauthBlockerMessage = nil
        authState = .authenticating

        if let restoredSession = await environment.authService.restoreSession() {
            authState = .loggedIn(restoredSession)
            statusMessage = nil
            environment.logger.info("Session restored successfully.")
            setRecorderState(.idle)
        } else {
            authState = .loggedOut
            statusMessage = "Login required to use dictation and read-aloud."
            environment.floatingBarManager.hide()
        }

        voicePreferences = environment.voicePreferencesStore.load()
        dictationRewritePreferences = environment.dictationRewritePreferencesStore.load()
        onboardingHotkeyConfirmed = environment.onboardingStateStore.hasCompletedHotkeyConfirmation()
        historyEntries = (try? environment.historyStore.load()) ?? []
    }

    public func login() async {
        if hasLocalCredential {
            statusMessage = "Login disabled in API key mode."
            return
        }

        guard activeProviderSupportsOAuth else {
            let message = "OAuth login is unavailable for \(authProviderDisplayName). Add an API key instead."
            authState = .authError(message)
            statusMessage = message
            return
        }

        guard canAttemptLogin else {
            authState = .authError(oauthBlockerMessage ?? "OAuth is currently unavailable.")
            statusMessage = oauthBlockerMessage ?? "OAuth is currently unavailable."
            return
        }

        authState = .authenticating

        do {
            let session = try await environment.authService.startOAuth()
            authState = .loggedIn(session)
            statusMessage = "Login successful."
            environment.logger.info("OAuth login completed.")
            setRecorderState(.idle)
        } catch {
            let message = localizedMessage(for: error)
            authState = .authError(message)
            statusMessage = message
            environment.logger.error("OAuth login failed: \(message)")
            environment.floatingBarManager.hide()
        }
    }

    public func saveProviderCredential(_ credential: String) {
        saveProviderCredential(credential, for: effectiveConfiguration.provider)
    }

    public func saveProviderCredential(_ credential: String, for provider: AIProvider) {
        let normalizedCredentials = parseCredentialInput(credential)
        guard !normalizedCredentials.isEmpty else {
            statusMessage = "API key is empty."
            return
        }

        saveProviderCredentialPool(normalizedCredentials, for: provider)
    }

    private func saveProviderCredentialPool(
        _ credentials: [String],
        for provider: AIProvider,
        successMessage: String? = nil,
        defaultModelForNewCredentials: String? = nil
    ) {
        let previousCredentials = savedCredentialTokens(for: provider)
        let previousModelOverrides = credentialRewriteModelOverrides(for: provider)
        let normalizedCredentials = normalizeCredentialPool(credentials)
        guard !normalizedCredentials.isEmpty else {
            statusMessage = "API key is empty."
            return
        }

        do {
            try environment.providerCredentialStore.saveCredentials(normalizedCredentials, for: provider.rawValue)
            includeProviderInFailoverRotation(provider)
            usesSavedProviderCredential = hasAnySavedProviderCredential
            let sessionToken = localCredentialToken ?? normalizedCredentials[0]
            let session = UserSession(
                accessToken: sessionToken,
                refreshToken: nil,
                tokenType: "Bearer",
                expiresAt: .distantFuture
            )
            authState = .loggedIn(session)
            oauthBlockerMessage = nil
            statusMessage = successMessage ?? defaultSavedCredentialsStatusMessage(for: provider, keyCount: normalizedCredentials.count)
            syncCredentialModelOverridesAfterCredentialSave(
                for: provider,
                previousCredentials: previousCredentials,
                newCredentials: normalizedCredentials,
                previousModelOverrides: previousModelOverrides,
                defaultModelForNewCredentials: defaultModelForNewCredentials
            )
            setRecorderState(.idle)
            configureHotkeysIfAllowed()
            environment.logger.info("Saved \(normalizedCredentials.count) \(provider.displayName) API key(s) to keychain.")
        } catch {
            let message = localizedMessage(for: error)
            statusMessage = message
            environment.logger.error("Failed to save \(provider.displayName) API key: \(message)")
        }
    }

    public func removeSavedProviderCredential() async {
        await removeSavedProviderCredential(for: effectiveConfiguration.provider)
    }

    public func removeSavedProviderCredential(for provider: AIProvider) async {
        do {
            try environment.providerCredentialStore.clearCredential(for: provider.rawValue)
            clearCredentialModelOverrides(for: provider)
            usesSavedProviderCredential = hasAnySavedProviderCredential
            environment.logger.info("Removed saved \(provider.displayName) API key.")
            await bootstrap()
        } catch {
            let message = localizedMessage(for: error)
            statusMessage = message
            environment.logger.error("Failed to remove \(provider.displayName) API key: \(message)")
        }
    }

    public func logout() async {
        if hasLocalCredential {
            if canRemoveSavedProviderCredential {
                await removeSavedProviderCredential()
                return
            }
            authState = .loggedIn(
                UserSession(
                    accessToken: localCredentialToken ?? "",
                    refreshToken: nil,
                    tokenType: "Bearer",
                    expiresAt: .distantFuture
                )
            )
            statusMessage = "Remove the saved API key from Provider Workbench to fully log out."
            return
        }

        await environment.authService.logout()
        authState = .loggedOut
        environment.hotkeyManager.stop()
        hotkeysEnabled = false
        setRecorderState(.idle)
        environment.floatingBarManager.hide()

        do {
            try environment.historyStore.clear()
            historyEntries = []
            statusMessage = "Logged out and history cleared."
            environment.logger.info("User logged out and history cleared.")
        } catch {
            statusMessage = localizedMessage(for: error)
            environment.logger.error("Failed to clear history during logout: \(statusMessage ?? "unknown")")
        }
    }

    public func refreshPermissions() {
        permissionStatus = environment.permissionsService.refreshStatus()
        configureHotkeysIfAllowed()
    }

    public func requestMicrophoneAccess() async {
        _ = await environment.permissionsService.requestMicrophoneAccess()
        refreshPermissions()
    }

    public func requestPermission(_ permission: PermissionKind) async {
        switch permission {
        case .microphone:
            _ = await environment.permissionsService.requestMicrophoneAccess()
        case .accessibility, .inputMonitoring:
            environment.permissionsService.openSystemSettings(for: permission)
        }
        refreshPermissions()
    }

    public func promptForRequiredPermissions() async {
        let requiredPermissions = missingPermissions
        guard !requiredPermissions.isEmpty else {
            statusMessage = "All required permissions are already granted."
            return
        }

        for permission in requiredPermissions {
            await requestPermission(permission)
        }

        if missingPermissions.isEmpty {
            statusMessage = "All required permissions are granted."
        } else {
            statusMessage = "Finish granting permissions in System Settings, then refresh."
        }
    }

    public func openSystemSettings(for permission: PermissionKind) {
        environment.permissionsService.openSystemSettings(for: permission)
        switch permission {
        case .microphone:
            statusMessage = "Grant microphone, then return here and press Refresh Permissions."
        case .accessibility, .inputMonitoring:
            statusMessage = "After enabling this permission, quit and reopen FloApp, then press Refresh Permissions."
        }
    }

    public func updateShortcut(action: ShortcutAction, combo: KeyCombo) {
        do {
            var byAction = Dictionary(uniqueKeysWithValues: shortcutBindings.map { ($0.action, $0) })
            var candidate = byAction[action] ?? ShortcutBinding(action: action, combo: combo)
            candidate.combo = combo
            candidate.enabled = true
            byAction[action] = candidate

            let normalized = Self.normalizedBindings(Array(byAction.values))
            try ShortcutBindingValidator.validate(normalized)

            environment.shortcutStore.saveBindings(normalized)
            shortcutBindings = normalized
            configureHotkeysIfAllowed()
            configureFloatingBarActions()
            statusMessage = nil
            environment.logger.info("Updated shortcut for \(action.displayName) to \(combo.humanReadable).")
        } catch {
            statusMessage = localizedMessage(for: error)
            environment.logger.error("Shortcut update failed: \(statusMessage ?? "unknown")")
        }
    }

    public func resetShortcutsToDefault() {
        let defaults = DefaultShortcuts.all
        environment.shortcutStore.saveBindings(defaults)
        shortcutBindings = defaults
        configureHotkeysIfAllowed()
        configureFloatingBarActions()
        environment.logger.info("Shortcuts reset to defaults.")
    }

    public func pasteLastTranscript() {
        guard let transcript = lastDictationTranscript else {
            statusMessage = "No transcript available yet."
            return
        }

        do {
            try ensurePermissionStatusForInjection()
            try environment.textInjectionService.inject(text: transcript)
            statusMessage = "Inserted last transcript."
        } catch {
            let copied = copyToClipboard(transcript)
            let errorMessage = localizedMessage(for: error)
            statusMessage = copied
                ? "\(errorMessage) Last transcript copied to clipboard."
                : "\(errorMessage) Could not copy last transcript to clipboard."
            environment.logger.error("Paste last transcript failed: \(errorMessage)")
        }
    }

    public func updateVoice(_ voice: String) {
        voicePreferences = VoicePreferences(voice: voice, speed: voicePreferences.speed)
        environment.voicePreferencesStore.save(voicePreferences)
        environment.logger.info("Updated TTS voice preference.")
    }

    public func updateVoiceSpeed(_ speed: Double) {
        let normalized = min(4.0, max(0.25, speed))
        voicePreferences = VoicePreferences(voice: voicePreferences.voice, speed: normalized)
        environment.voicePreferencesStore.save(voicePreferences)
        environment.logger.info("Updated TTS speed preference.")
    }

    public func setLiveDictationEnabled(_ enabled: Bool) {
        liveDictationEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.liveDictationUserDefaultsKey)
        updateDictationRewritePreferences { preferences in
            DictationRewritePreferences(
                rewriteEnabled: preferences.rewriteEnabled,
                liveTypingEnabled: enabled,
                liveFinalizationMode: preferences.liveFinalizationMode,
                baseTone: preferences.baseTone,
                warmth: preferences.warmth,
                enthusiasm: preferences.enthusiasm,
                headersAndLists: preferences.headersAndLists,
                emoji: preferences.emoji,
                customInstructions: preferences.customInstructions
            )
        }
        if enabled {
            statusMessage = "Live dictation enabled. Flo will type partial transcript while you speak."
        } else {
            liveTranscriptPreview = ""
            statusMessage = "Live dictation disabled."
        }
    }

    public func setDictationRewriteEnabled(_ enabled: Bool) {
        updateDictationRewritePreferences { preferences in
            DictationRewritePreferences(
                rewriteEnabled: enabled,
                liveTypingEnabled: preferences.liveTypingEnabled,
                liveFinalizationMode: preferences.liveFinalizationMode,
                baseTone: preferences.baseTone,
                warmth: preferences.warmth,
                enthusiasm: preferences.enthusiasm,
                headersAndLists: preferences.headersAndLists,
                emoji: preferences.emoji,
                customInstructions: preferences.customInstructions
            )
        }
        statusMessage = enabled ? "Dictation rewrite enabled." : "Dictation rewrite disabled."
    }

    public func setDictationBaseTone(_ tone: DictationBaseTone) {
        updateDictationRewritePreferences { preferences in
            DictationRewritePreferences(
                rewriteEnabled: preferences.rewriteEnabled,
                liveTypingEnabled: preferences.liveTypingEnabled,
                liveFinalizationMode: preferences.liveFinalizationMode,
                baseTone: tone,
                warmth: preferences.warmth,
                enthusiasm: preferences.enthusiasm,
                headersAndLists: preferences.headersAndLists,
                emoji: preferences.emoji,
                customInstructions: preferences.customInstructions
            )
        }
    }

    public func setDictationWarmth(_ level: DictationStyleLevel) {
        updateDictationRewritePreferences { preferences in
            DictationRewritePreferences(
                rewriteEnabled: preferences.rewriteEnabled,
                liveTypingEnabled: preferences.liveTypingEnabled,
                liveFinalizationMode: preferences.liveFinalizationMode,
                baseTone: preferences.baseTone,
                warmth: level,
                enthusiasm: preferences.enthusiasm,
                headersAndLists: preferences.headersAndLists,
                emoji: preferences.emoji,
                customInstructions: preferences.customInstructions
            )
        }
    }

    public func setDictationEnthusiasm(_ level: DictationStyleLevel) {
        updateDictationRewritePreferences { preferences in
            DictationRewritePreferences(
                rewriteEnabled: preferences.rewriteEnabled,
                liveTypingEnabled: preferences.liveTypingEnabled,
                liveFinalizationMode: preferences.liveFinalizationMode,
                baseTone: preferences.baseTone,
                warmth: preferences.warmth,
                enthusiasm: level,
                headersAndLists: preferences.headersAndLists,
                emoji: preferences.emoji,
                customInstructions: preferences.customInstructions
            )
        }
    }

    public func setDictationHeadersAndLists(_ level: DictationStyleLevel) {
        updateDictationRewritePreferences { preferences in
            DictationRewritePreferences(
                rewriteEnabled: preferences.rewriteEnabled,
                liveTypingEnabled: preferences.liveTypingEnabled,
                liveFinalizationMode: preferences.liveFinalizationMode,
                baseTone: preferences.baseTone,
                warmth: preferences.warmth,
                enthusiasm: preferences.enthusiasm,
                headersAndLists: level,
                emoji: preferences.emoji,
                customInstructions: preferences.customInstructions
            )
        }
    }

    public func setDictationEmoji(_ level: DictationStyleLevel) {
        updateDictationRewritePreferences { preferences in
            DictationRewritePreferences(
                rewriteEnabled: preferences.rewriteEnabled,
                liveTypingEnabled: preferences.liveTypingEnabled,
                liveFinalizationMode: preferences.liveFinalizationMode,
                baseTone: preferences.baseTone,
                warmth: preferences.warmth,
                enthusiasm: preferences.enthusiasm,
                headersAndLists: preferences.headersAndLists,
                emoji: level,
                customInstructions: preferences.customInstructions
            )
        }
    }

    public func setDictationCustomInstructions(_ text: String) {
        updateDictationRewritePreferences { preferences in
            DictationRewritePreferences(
                rewriteEnabled: preferences.rewriteEnabled,
                liveTypingEnabled: preferences.liveTypingEnabled,
                liveFinalizationMode: preferences.liveFinalizationMode,
                baseTone: preferences.baseTone,
                warmth: preferences.warmth,
                enthusiasm: preferences.enthusiasm,
                headersAndLists: preferences.headersAndLists,
                emoji: preferences.emoji,
                customInstructions: text
            )
        }
    }

    public func setDictationLiveFinalizationMode(_ mode: DictationLiveFinalizationMode) {
        updateDictationRewritePreferences { preferences in
            DictationRewritePreferences(
                rewriteEnabled: preferences.rewriteEnabled,
                liveTypingEnabled: preferences.liveTypingEnabled,
                liveFinalizationMode: mode,
                baseTone: preferences.baseTone,
                warmth: preferences.warmth,
                enthusiasm: preferences.enthusiasm,
                headersAndLists: preferences.headersAndLists,
                emoji: preferences.emoji,
                customInstructions: preferences.customInstructions
            )
        }

        switch mode {
        case .appendOnly:
            statusMessage = "Live finalization: append missing final text."
        case .replaceWithFinal:
            statusMessage = "Live finalization: replace live draft with final rewrite."
        }
    }

    public func applyDictationRewritePreset(_ preset: DictationRewritePreset) {
        let profile = Self.rewriteProfile(for: preset)
        updateDictationRewritePreferences { preferences in
            DictationRewritePreferences(
                rewriteEnabled: preferences.rewriteEnabled,
                liveTypingEnabled: preferences.liveTypingEnabled,
                liveFinalizationMode: preferences.liveFinalizationMode,
                baseTone: profile.baseTone,
                warmth: profile.warmth,
                enthusiasm: profile.enthusiasm,
                headersAndLists: profile.headersAndLists,
                emoji: profile.emoji,
                customInstructions: preferences.customInstructions
            )
        }

        statusMessage = "Applied \(preset.displayName) rewrite preset."
    }

    public func completeHotkeyConfirmation() {
        onboardingHotkeyConfirmed = true
        environment.onboardingStateStore.setHotkeyConfirmationCompleted(true)
        environment.logger.info("Onboarding hotkey confirmation completed.")
    }

    public func clearHistory() {
        do {
            try environment.historyStore.clear()
            historyEntries = []
            statusMessage = "History cleared."
            environment.logger.info("Session history cleared.")
        } catch {
            statusMessage = localizedMessage(for: error)
            environment.logger.error("Failed to clear history: \(statusMessage ?? "unknown")")
        }
    }

    public func startDictationFromHotkey() async {
        guard featureFlags.enableDictation else {
            transitionToError(localizedMessage(for: FloError.featureDisabled("Dictation")), kind: .dictation, inputText: "")
            return
        }

        guard !isDictationListening else {
            return
        }

        guard isAuthenticated else {
            transitionToError(localizedMessage(for: FloError.unauthorized), kind: .dictation, inputText: "")
            return
        }

        do {
            try ensurePermissionStatusForDictationStart()
            liveInjectedTranscript = ""
            didPauseLiveTypingAfterError = false
            lastLiveInjectionAt = .distantPast
            liveTranscriptPreview = ""

            if liveDictationEnabled {
                try ensurePermissionStatusForInjection()
                try environment.speechCaptureService.startCapture(
                    levelHandler: { [weak self] level in
                        Task { @MainActor in
                            self?.latestAudioLevel = level
                            self?.environment.floatingBarManager.updateAudioLevel(level)
                        }
                    },
                    transcriptHandler: { [weak self] partial in
                        Task { @MainActor in
                            self?.handleLiveTranscript(partial)
                        }
                    }
                )
            } else {
                try environment.speechCaptureService.startCapture(levelHandler: { [weak self] level in
                    Task { @MainActor in
                        self?.latestAudioLevel = level
                        self?.environment.floatingBarManager.updateAudioLevel(level)
                    }
                })
            }

            isDictationListening = true
            setRecorderState(.listening)
            statusMessage = nil
        } catch {
            transitionToError(localizedMessage(for: error), kind: .dictation, inputText: "")
        }
    }

    public func stopDictationFromHotkey() async {
        guard isDictationListening else {
            return
        }
        isDictationListening = false
        var transcribedText: String?
        var rawTranscribedText: String?
        var transcriptRequestID: String?
        var transcriptLatencyMs: Int?
        var transcriptConfidence: Double?

        do {
            let audioURL = try environment.speechCaptureService.stopCapture()
            setRecorderState(.transcribing)
            defer { cleanupAudioArtifact(at: audioURL) }

            let session = try await validatedSession()
            let liveFallbackTranscript = liveInjectedTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            var transcriptionFallbackNotice: String?
            let normalizedText: String
            do {
                let transcriptResult = try await environment.transcriptionService.transcribe(
                    audioFileURL: audioURL,
                    authToken: session.accessToken
                )
                let candidate = transcriptResult.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !candidate.isEmpty else {
                    throw FloError.emptyAudio
                }
                normalizedText = candidate
                transcriptRequestID = transcriptResult.requestID
                transcriptLatencyMs = transcriptResult.latencyMs
                transcriptConfidence = transcriptResult.confidence
            } catch {
                guard !liveFallbackTranscript.isEmpty else {
                    throw error
                }
                normalizedText = liveFallbackTranscript
                transcriptRequestID = nil
                transcriptLatencyMs = nil
                transcriptConfidence = nil
                transcriptionFallbackNotice = "Provider transcription failed; used live transcript fallback."
                environment.logger.error("Provider transcription failed, used live fallback: \(localizedMessage(for: error))")
            }

            rawTranscribedText = normalizedText

            var finalizedText = normalizedText
            var rewriteStatusNotice: String?
            if dictationRewritePreferences.rewriteEnabled {
                do {
                    let rewritten = try await environment.dictationRewriteService.rewrite(
                        transcript: normalizedText,
                        authToken: session.accessToken,
                        preferences: dictationRewritePreferences
                    ).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !rewritten.isEmpty {
                        finalizedText = rewritten
                        if rewritten != normalizedText {
                            rewriteStatusNotice = "Applied style rewrite."
                        }
                    }
                } catch {
                    rewriteStatusNotice = "Rewrite failed, used raw transcript."
                    environment.logger.error("Dictation rewrite failed: \(localizedMessage(for: error))")
                }
            }
            transcribedText = finalizedText

            let copiedForRecovery = copyToClipboard(finalizedText)
            if !copiedForRecovery {
                environment.logger.error("Could not copy transcript to clipboard before injection.")
            }

            var textToInject = finalizedText
            var shouldReplaceLiveText = false
            var liveReconciliationNotice: String?
            if liveDictationEnabled, !liveInjectedTranscript.isEmpty {
                switch dictationRewritePreferences.liveFinalizationMode {
                case .appendOnly:
                    if finalizedText.hasPrefix(liveInjectedTranscript) {
                        textToInject = String(finalizedText.dropFirst(liveInjectedTranscript.count))
                    } else {
                        textToInject = ""
                        liveReconciliationNotice =
                            "Live transcript differed from final model output. Final transcript copied to clipboard."
                    }
                case .replaceWithFinal:
                    shouldReplaceLiveText = true
                    liveReconciliationNotice = "Replaced live draft with final transcript."
                }
            }

            do {
                if shouldReplaceLiveText {
                    if liveInjectedTranscript != finalizedText {
                        setRecorderState(.injecting)
                        try ensurePermissionStatusForInjection()
                        try environment.textInjectionService.replaceRecentText(
                            previousText: liveInjectedTranscript,
                            with: finalizedText
                        )
                    }
                } else if !textToInject.isEmpty {
                    setRecorderState(.injecting)
                    try ensurePermissionStatusForInjection()
                    try environment.textInjectionService.inject(text: textToInject)
                }
            } catch {
                let copied = copiedForRecovery || copyToClipboard(finalizedText)
                let errorMessage = localizedMessage(for: error)
                let specificMessage: String? = {
                    guard let floError = error as? FloError else {
                        return nil
                    }
                    switch floError {
                    case .permissionDenied, .secureInputActive:
                        return errorMessage
                    default:
                        return nil
                    }
                }()
                let fallbackMessage: String
                if let specificMessage {
                    fallbackMessage = copied
                        ? "\(specificMessage) Transcript copied to clipboard."
                        : "\(specificMessage) Could not copy transcript to clipboard."
                } else {
                    fallbackMessage = copied
                        ? "Could not inject into focused app. Transcript copied to clipboard."
                        : "Could not inject into focused app."
                }

                let entry = HistoryEntry(
                    kind: .dictation,
                    inputText: rawTranscribedText ?? finalizedText,
                    outputText: finalizedText,
                    requestID: transcriptRequestID,
                    latencyMs: transcriptLatencyMs,
                    success: false,
                    errorMessage: errorMessage
                )
                appendHistoryBestEffort(entry)

                statusMessage = fallbackMessage
                environment.logger.error("Injection failed: \(errorMessage)")
                setRecorderState(.idle)
                return
            }

            liveTranscriptPreview = finalizedText
            let entry = HistoryEntry(
                kind: .dictation,
                inputText: rawTranscribedText ?? finalizedText,
                outputText: finalizedText,
                requestID: transcriptRequestID,
                latencyMs: transcriptLatencyMs,
                success: true,
                errorMessage: nil
            )
            appendHistoryBestEffort(entry)

            let confidenceSuffix = transcriptConfidence.map { " (confidence: \(String(format: "%.2f", $0)))" } ?? ""
            let clipboardRecovered = copiedForRecovery || copyToClipboard(finalizedText)
            let clipboardSuffix = clipboardRecovered
                ? " Transcript copied to clipboard."
                : " Could not copy transcript to clipboard."
            let liveSuffix = liveReconciliationNotice.map { " \($0)" } ?? ""
            let rewriteSuffix = rewriteStatusNotice.map { " \($0)" } ?? ""
            let fallbackSuffix = transcriptionFallbackNotice.map { " \($0)" } ?? ""
            let baseMessage = liveDictationEnabled ? "Live dictation completed." : "Dictation inserted."
            statusMessage = "\(baseMessage)\(confidenceSuffix)\(clipboardSuffix)\(rewriteSuffix)\(liveSuffix)\(fallbackSuffix)"
            setRecorderState(.idle)
        } catch {
            if let transcribedText {
                let copied = copyToClipboard(transcribedText)
                let errorMessage = localizedMessage(for: error)
                let fallbackMessage = copied
                    ? "\(errorMessage) Transcript copied to clipboard."
                    : "\(errorMessage) Could not copy transcript to clipboard."

                let entry = HistoryEntry(
                    kind: .dictation,
                    inputText: rawTranscribedText ?? transcribedText,
                    outputText: transcribedText,
                    requestID: transcriptRequestID,
                    latencyMs: transcriptLatencyMs,
                    success: false,
                    errorMessage: errorMessage
                )
                appendHistoryBestEffort(entry)

                statusMessage = fallbackMessage
                environment.logger.error("Dictation failed after transcription: \(errorMessage)")
                setRecorderState(.idle)
                return
            }
            transitionToError(localizedMessage(for: error), kind: .dictation, inputText: "")
        }
    }

    private func handleLiveTranscript(_ partial: String) {
        guard liveDictationEnabled, isDictationListening else {
            return
        }

        let normalized = partial
        guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        liveTranscriptPreview = normalized
        guard !didPauseLiveTypingAfterError else {
            return
        }
        guard normalized.count >= liveInjectedTranscript.count else {
            return
        }
        guard normalized.hasPrefix(liveInjectedTranscript) else {
            // Ignore unstable partial rewrites; final reconciliation happens on stop.
            return
        }

        let delta = String(normalized.dropFirst(liveInjectedTranscript.count))
        guard shouldInjectLiveDelta(delta) else {
            return
        }

        do {
            try environment.textInjectionService.inject(text: delta)
            liveInjectedTranscript = normalized
            lastLiveInjectionAt = Date()
        } catch {
            didPauseLiveTypingAfterError = true
            let message = localizedMessage(for: error)
            statusMessage = "Live typing paused: \(message). Final transcript will still complete."
            environment.logger.error("Live typing injection failed: \(message)")
        }
    }

    private func shouldInjectLiveDelta(_ delta: String) -> Bool {
        guard !delta.isEmpty else {
            return false
        }

        let elapsed = Date().timeIntervalSince(lastLiveInjectionAt)
        let hasBoundary = delta.hasSuffix(" ") || delta.contains { ".!?,:\n".contains($0) }
        if elapsed < 0.25, delta.count < 8, !hasBoundary {
            return false
        }

        return true
    }

    private static func rewriteProfile(for preset: DictationRewritePreset) -> (
        baseTone: DictationBaseTone,
        warmth: DictationStyleLevel,
        enthusiasm: DictationStyleLevel,
        headersAndLists: DictationStyleLevel,
        emoji: DictationStyleLevel
    ) {
        switch preset {
        case .default:
            return (.default, .default, .default, .default, .less)
        case .professional:
            return (.professional, .less, .less, .more, .less)
        case .friendly:
            return (.friendly, .more, .default, .default, .default)
        case .candid:
            return (.candid, .default, .less, .default, .less)
        case .efficient:
            return (.efficient, .less, .less, .more, .less)
        case .nerdy:
            return (.nerdy, .default, .more, .more, .less)
        case .quirky:
            return (.quirky, .more, .more, .default, .more)
        }
    }

    private func updateDictationRewritePreferences(
        _ mutate: (DictationRewritePreferences) -> DictationRewritePreferences
    ) {
        let updated = mutate(dictationRewritePreferences)
        dictationRewritePreferences = updated
        environment.dictationRewritePreferencesStore.save(updated)
    }

    private func readSelectedTextWithRetry(maxAttempts: Int = 4) async throws -> String {
        var lastError: Error = FloError.noSelectedText
        for attempt in 0..<maxAttempts {
            do {
                return try environment.selectionReaderService.getSelectedText()
            } catch {
                lastError = error
                if let floError = error as? FloError, case .noSelectedText = floError, attempt < maxAttempts - 1 {
                    try? await Task.sleep(nanoseconds: 70_000_000)
                    continue
                }
                throw error
            }
        }
        throw lastError
    }

    public func readSelectedTextFromHotkey() async {
        guard featureFlags.enableReadAloud else {
            transitionToError(localizedMessage(for: FloError.featureDisabled("Read-aloud")), kind: .readAloud, inputText: "")
            return
        }

        do {
            let session = try await validatedSession()
            try ensurePermissionStatusForReadAloud()
            let selectedText = try await readSelectedTextWithRetry()
            let normalized = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else {
                throw FloError.noSelectedText
            }

            setRecorderState(.speaking)
            try await environment.ttsService.synthesizeAndPlay(
                text: normalized,
                authToken: session.accessToken,
                voice: voicePreferences.voice,
                speed: voicePreferences.speed
            )

            let entry = HistoryEntry(
                kind: .readAloud,
                inputText: normalized,
                outputText: nil,
                requestID: nil,
                latencyMs: nil,
                success: true,
                errorMessage: nil
            )
            appendHistoryBestEffort(entry)

            statusMessage = "Read-aloud completed."
            setRecorderState(.idle)
        } catch is CancellationError {
            statusMessage = "Read-aloud canceled."
            if recorderState == .speaking {
                setRecorderState(.idle)
            }
        } catch {
            transitionToError(localizedMessage(for: error), kind: .readAloud, inputText: "")
        }
    }

    public func previewCurrentVoice() async {
        guard featureFlags.enableReadAloud else {
            statusMessage = localizedMessage(for: FloError.featureDisabled("Read-aloud"))
            return
        }
        guard !isVoicePreviewInProgress else {
            return
        }
        guard recorderState == .idle else {
            statusMessage = "Wait for the current action to finish, then try voice preview again."
            return
        }

        do {
            let session = try await validatedSession()
            isVoicePreviewInProgress = true
            setRecorderState(.speaking)
            statusMessage = "Playing voice preview..."
            defer {
                isVoicePreviewInProgress = false
                if recorderState == .speaking {
                    setRecorderState(.idle)
                }
            }

            try await environment.ttsService.synthesizeAndPlay(
                text: Self.voicePreviewText,
                authToken: session.accessToken,
                voice: voicePreferences.voice,
                speed: voicePreferences.speed
            )

            statusMessage = "Voice preview completed."
        } catch is CancellationError {
            statusMessage = "Voice preview canceled."
            if recorderState == .speaking {
                setRecorderState(.idle)
            }
        } catch {
            let message = localizedMessage(for: error)
            statusMessage = message
            environment.logger.error("Voice preview failed: \(message)")
        }
    }

    private func configureHotkeysIfAllowed() {
        guard featureFlags.enableGlobalHotkeys else {
            environment.hotkeyManager.stop()
            hotkeysEnabled = false
            statusMessage = statusMessage ?? localizedMessage(for: FloError.featureDisabled("Global hotkeys"))
            return
        }

        guard permissionStatus.accessibility == .granted,
              permissionStatus.inputMonitoring == .granted
        else {
            environment.hotkeyManager.stop()
            hotkeysEnabled = false
            return
        }

        environment.hotkeyManager.start(
            bindings: shortcutBindings,
            handlers: HotkeyHandlers(
                dictationStarted: { [weak self] in
                    Task { @MainActor in
                        await self?.startDictationFromHotkey()
                    }
                },
                dictationStopped: { [weak self] in
                    Task { @MainActor in
                        await self?.stopDictationFromHotkey()
                    }
                },
                readSelectedTriggered: { [weak self] in
                    Task { @MainActor in
                        await self?.readSelectedTextFromHotkey()
                    }
                }
            )
        )

        hotkeysEnabled = true
    }

    private func configureFloatingBarActions() {
        let dictationHint = "Hold \(shortcutDisplay(for: .dictationHold)) to start dictating, or click to toggle."
        let readHint = "Press \(shortcutDisplay(for: .readSelectedText)) or click to narrate selected text."
        environment.floatingBarManager.setActions(
            FloatingBarActions(
                toggleDictation: { [weak self] in
                    Task { @MainActor in
                        await self?.toggleDictationFromFloatingBar()
                    }
                },
                triggerReadSelected: { [weak self] in
                    Task { @MainActor in
                        await self?.toggleReadSelectedFromFloatingBar()
                    }
                },
                openMainWindow: {
                    NSApp.activate(ignoringOtherApps: true)
                },
                dictationHint: dictationHint,
                readSelectedHint: readHint
            )
        )
    }

    private func shortcutDisplay(for action: ShortcutAction) -> String {
        if let binding = shortcutBindings.first(where: { $0.action == action }) {
            return binding.combo.humanReadable
        }
        switch action {
        case .dictationHold:
            return DefaultShortcuts.dictation.combo.humanReadable
        case .readSelectedText:
            return DefaultShortcuts.readSelected.combo.humanReadable
        case .pushToTalkToggle:
            return "push-to-talk"
        }
    }

    private func toggleDictationFromFloatingBar() async {
        if isDictationListening {
            await stopDictationFromHotkey()
        } else {
            await startDictationFromHotkey()
        }
    }

    private func toggleReadSelectedFromFloatingBar() async {
        if recorderState == .speaking {
            environment.ttsService.stopPlayback()
            statusMessage = "Read-aloud canceled."
            setRecorderState(.idle)
            return
        }
        await readSelectedTextFromHotkey()
    }

    private func setRecorderState(_ newState: RecorderState) {
        let oldState = recorderState
        recorderState = newState

        switch newState {
        case .idle:
            if isAuthenticated {
                environment.floatingBarManager.update(state: .idle)
                environment.floatingBarManager.show(state: .idle)
            } else {
                environment.floatingBarManager.hide()
            }
        default:
            if case .idle = oldState {
                environment.floatingBarManager.show(state: newState)
            } else {
                environment.floatingBarManager.update(state: newState)
            }
        }
    }

    private func transitionToError(_ message: String, kind: HistoryEventKind, inputText: String) {
        setRecorderState(.error(message))
        statusMessage = message
        environment.logger.error(message)

        let failedEntry = HistoryEntry(
            kind: kind,
            inputText: inputText,
            outputText: nil,
            requestID: nil,
            latencyMs: nil,
            success: false,
            errorMessage: message
        )
        appendHistoryBestEffort(failedEntry)

        stateResetTask?.cancel()
        stateResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                self?.setRecorderState(.idle)
            }
        }
    }

    private func validatedSession() async throws -> UserSession {
        switch authState {
        case .loggedIn(let session):
            if session.expiresAt.timeIntervalSinceNow > 60 {
                return session
            }

            let refreshed = try await environment.authService.refreshSession(session)
            authState = .loggedIn(refreshed)
            return refreshed
        default:
            throw FloError.unauthorized
        }
    }

    private func appendHistory(_ entry: HistoryEntry) throws {
        try environment.historyStore.append(entry)
        historyEntries.insert(entry, at: 0)
        if historyEntries.count > 300 {
            historyEntries = Array(historyEntries.prefix(300))
        }
    }

    private func appendHistoryBestEffort(_ entry: HistoryEntry) {
        do {
            try appendHistory(entry)
        } catch {
            environment.logger.error("Failed to persist history entry: \(localizedMessage(for: error))")
        }
    }

    private func cleanupAudioArtifact(at url: URL) {
        guard !environment.configuration.retainAudioDebugArtifacts else {
            return
        }
        try? FileManager.default.removeItem(at: url)
    }

    private func ensurePermissionStatusForDictationStart() throws {
        if permissionStatus.microphone != .granted {
            throw FloError.permissionDenied("Microphone")
        }
        if permissionStatus.inputMonitoring != .granted {
            throw FloError.permissionDenied("Input Monitoring")
        }
    }

    private func ensurePermissionStatusForInjection() throws {
        if permissionStatus.accessibility != .granted {
            throw FloError.permissionDenied("Accessibility")
        }
        if permissionStatus.inputMonitoring != .granted {
            throw FloError.permissionDenied("Input Monitoring")
        }
    }

    private func ensurePermissionStatusForReadAloud() throws {
        if permissionStatus.accessibility != .granted {
            throw FloError.permissionDenied("Accessibility")
        }
        if permissionStatus.inputMonitoring != .granted {
            throw FloError.permissionDenied("Input Monitoring")
        }
    }

    private func parseCredentialInput(_ raw: String) -> [String] {
        let values = raw
            .split { $0 == "," || $0 == ";" || $0 == "\n" || $0 == "\t" }
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        return normalizeCredentialPool(values)
    }

    private func normalizeCredentialPool(_ credentials: [String]) -> [String] {
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

    private func defaultSavedCredentialsStatusMessage(for provider: AIProvider, keyCount: Int) -> String {
        if keyCount == 1 {
            return "\(provider.displayName) API key saved in keychain."
        }
        return "\(provider.displayName) API keys saved in keychain (\(keyCount))."
    }

    private func localizedMessage(for error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }

    private func copyToClipboard(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    private static let voicePreviewText = "Hi, this is Flo. This is how your selected voice sounds."

    private static func normalizedBindings(_ bindings: [ShortcutBinding]) -> [ShortcutBinding] {
        let allActions: [ShortcutAction] = [.dictationHold, .readSelectedText]
        var byAction = Dictionary(uniqueKeysWithValues: bindings.map { ($0.action, $0) })
        for required in DefaultShortcuts.all where byAction[required.action] == nil {
            byAction[required.action] = required
        }
        return allActions.compactMap { byAction[$0] }
    }
}
