import AppCore
import AppKit
import Combine
import Foundation

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
        if environment.configuration.provider == .gemini {
            return false
        }
        return oauthBlockerMessage == nil
    }

    public var authProviderDisplayName: String {
        environment.configuration.providerDisplayName
    }

    public var supportedVoices: [String] {
        VoiceCatalog.supportedVoices(for: environment.configuration.provider)
    }

    public var featureFlags: FeatureFlags {
        environment.configuration.featureFlags
    }

    public var manualUpdateURL: URL? {
        environment.configuration.manualUpdateURL
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
        switch activeLocalCredential?.source {
        case .keychain:
            return "Saved in app keychain"
        case .environment:
            return "Loaded from \(localCredentialEnvVarName)"
        case .none:
            return nil
        }
    }

    public var canRemoveSavedProviderCredential: Bool {
        guard let source = activeLocalCredential?.source else {
            return false
        }
        return source == .keychain
    }

    private let environment: AppEnvironment
    private var isDictationListening = false
    private var stateResetTask: Task<Void, Never>?
    private var liveInjectedTranscript = ""
    private var didPauseLiveTypingAfterError = false
    private var lastLiveInjectionAt = Date.distantPast
    private enum LocalCredentialSource {
        case keychain
        case environment
    }
    private static let liveDictationUserDefaultsKey = "flo.live_dictation_enabled"

    private var savedCredentialToken: String? {
        environment.providerCredentialStore
            .credential(for: providerIdentifier)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var environmentCredentialToken: String? {
        environment.configuration.localCredentialToken?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var activeLocalCredential: (token: String, source: LocalCredentialSource)? {
        if let saved = savedCredentialToken, !saved.isEmpty {
            return (saved, .keychain)
        }
        if let environmentCredentialToken, !environmentCredentialToken.isEmpty {
            return (environmentCredentialToken, .environment)
        }
        return nil
    }

    private var localCredentialToken: String? {
        activeLocalCredential?.token
    }

    private var providerIdentifier: String {
        environment.configuration.provider.rawValue
    }

    private var hasLocalCredential: Bool {
        guard let key = localCredentialToken else {
            return false
        }
        return !key.isEmpty
    }

    private var localCredentialEnvVarName: String {
        switch environment.configuration.provider {
        case .openai:
            return "FLO_OPENAI_API_KEY"
        case .gemini:
            return "FLO_GEMINI_API_KEY"
        }
    }

    public init(environment: AppEnvironment) {
        self.environment = environment

        let loadedBindings = environment.shortcutStore.loadBindings()
        self.shortcutBindings = Self.normalizedBindings(loadedBindings)
        self.permissionStatus = environment.permissionsService.refreshStatus()
        self.historyEntries = (try? environment.historyStore.load()) ?? []
        self.voicePreferences = environment.voicePreferencesStore.load()
        self.dictationRewritePreferences = environment.dictationRewritePreferencesStore.load()
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
        configureFloatingBarActions()
        refreshPermissions()
        configureHotkeysIfAllowed()
        usesSavedProviderCredential = activeLocalCredential?.source == .keychain

        if hasLocalCredential {
            let keySession = UserSession(
                accessToken: localCredentialToken ?? "",
                refreshToken: nil,
                tokenType: "Bearer",
                expiresAt: .distantFuture
            )
            authState = .loggedIn(keySession)
            statusMessage = "Using \(authProviderDisplayName) API key mode."
            oauthBlockerMessage = nil
            environment.logger.info(
                "Running in \(authProviderDisplayName) API key mode from \(providerCredentialSourceLabel ?? "local credential")."
            )
            setRecorderState(.idle)
            voicePreferences = environment.voicePreferencesStore.load()
            dictationRewritePreferences = environment.dictationRewritePreferencesStore.load()
            onboardingHotkeyConfirmed = environment.onboardingStateStore.hasCompletedHotkeyConfirmation()
            historyEntries = (try? environment.historyStore.load()) ?? []
            return
        }

        if environment.configuration.provider == .gemini {
            let blocker = "Gemini API key missing. Add one below or set \(localCredentialEnvVarName) in .env.local."
            oauthBlockerMessage = blocker
            authState = .authError(blocker)
            statusMessage = blocker
            environment.logger.error(blocker)
            environment.floatingBarManager.hide()
            historyEntries = (try? environment.historyStore.load()) ?? []
            return
        }

        if environment.configuration.oauth == nil {
            let blocker = "OAuth is blocked: ChatGPT OAuth is disabled for this build."
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

        if environment.configuration.provider == .gemini {
            statusMessage = "Add a Gemini API key in-app or set \(localCredentialEnvVarName) in .env.local."
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
        let trimmed = credential.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusMessage = "API key is empty."
            return
        }

        do {
            try environment.providerCredentialStore.saveCredential(trimmed, for: providerIdentifier)
            usesSavedProviderCredential = true
            let session = UserSession(
                accessToken: trimmed,
                refreshToken: nil,
                tokenType: "Bearer",
                expiresAt: .distantFuture
            )
            authState = .loggedIn(session)
            oauthBlockerMessage = nil
            statusMessage = "\(authProviderDisplayName) API key saved in keychain."
            setRecorderState(.idle)
            configureHotkeysIfAllowed()
            environment.logger.info("Saved \(authProviderDisplayName) API key to keychain.")
        } catch {
            let message = localizedMessage(for: error)
            statusMessage = message
            environment.logger.error("Failed to save \(authProviderDisplayName) API key: \(message)")
        }
    }

    public func removeSavedProviderCredential() async {
        do {
            try environment.providerCredentialStore.clearCredential(for: providerIdentifier)
            usesSavedProviderCredential = false
            environment.logger.info("Removed saved \(authProviderDisplayName) API key.")
            await bootstrap()
        } catch {
            let message = localizedMessage(for: error)
            statusMessage = message
            environment.logger.error("Failed to remove \(authProviderDisplayName) API key: \(message)")
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
            statusMessage = "Unset \(localCredentialEnvVarName) in .env.local to fully log out."
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
