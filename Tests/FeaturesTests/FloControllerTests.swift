import AppCore
import AppKit
import Features
import Foundation
import Infrastructure
import Testing

@Suite("FloController Tests", .serialized)
struct FloControllerTests {
    @Test
    @MainActor
    func bootstrapWithoutOAuthSetsExplicitBlockerState() async {
        let dependencies = TestDependencies(configuration: makeConfiguration(oauth: nil))
        let controller = FloController(environment: dependencies.environment)

        await controller.bootstrap()

        #expect(controller.canAttemptLogin == false)
        #expect(controller.oauthBlockerMessage != nil)

        switch controller.authState {
        case .authError:
            break
        default:
            Issue.record("Expected authError when OAuth configuration is missing")
        }
    }

    @Test
    @MainActor
    func bootstrapWithGeminiKeyUsesLocalCredentialMode() async {
        let configuration = makeConfiguration(
            oauth: nil,
            provider: .gemini,
            geminiApiKey: nil
        )
        let dependencies = TestDependencies(configuration: configuration)
        dependencies.providerCredentialStore.credentials["gemini"] = "gemini_key_123"
        let controller = FloController(environment: dependencies.environment)

        await controller.bootstrap()

        #expect(controller.isAuthenticated == true)
        #expect(controller.statusMessage == "Using API key mode with provider failover.")
        #expect(controller.canAttemptLogin == false)
    }

    @Test
    @MainActor
    func bootstrapWithoutKeyForNonOAuthProviderRequiresApiKey() async {
        let configuration = makeConfiguration(
            oauth: sampleOAuthConfiguration(),
            provider: .openrouter,
            geminiApiKey: nil
        )
        let dependencies = TestDependencies(configuration: configuration)
        let controller = FloController(environment: dependencies.environment)

        await controller.bootstrap()

        #expect(controller.canAttemptLogin == false)
        #expect(controller.oauthBlockerMessage?.contains("No API keys found for OpenRouter") == true)

        switch controller.authState {
        case .authError:
            break
        default:
            Issue.record("Expected authError when active provider requires API key auth.")
        }
    }

    @Test
    @MainActor
    func saveProviderCredentialEnablesGeminiKeyMode() async {
        let configuration = makeConfiguration(oauth: nil, provider: .gemini, geminiApiKey: nil)
        let dependencies = TestDependencies(configuration: configuration)
        let controller = FloController(environment: dependencies.environment)

        await controller.bootstrap()
        controller.saveProviderCredential("gemini_saved_123")

        #expect(controller.isAuthenticated == true)
        #expect(dependencies.providerCredentialStore.credential(for: "gemini") == "gemini_saved_123")
        #expect(controller.statusMessage == "Gemini API key saved in keychain.")
    }

    @Test
    @MainActor
    func saveProviderCredentialParsesAndStoresMultipleKeys() async {
        let configuration = makeConfiguration(oauth: nil, provider: .gemini, geminiApiKey: nil)
        let dependencies = TestDependencies(configuration: configuration)
        let controller = FloController(environment: dependencies.environment)

        await controller.bootstrap()
        controller.saveProviderCredential("gemini_saved_1, gemini_saved_2\ngemini_saved_3")

        #expect(dependencies.providerCredentialStore.credentialPools["gemini"] == [
            "gemini_saved_1",
            "gemini_saved_2",
            "gemini_saved_3"
        ])
        #expect(controller.statusMessage == "Gemini API keys saved in keychain (3).")
    }

    @Test
    @MainActor
    func saveProviderCredentialForNonPrimaryProviderIsSupported() async {
        let configuration = makeConfiguration(oauth: sampleOAuthConfiguration(), provider: .openai, geminiApiKey: nil)
        let dependencies = TestDependencies(configuration: configuration)
        let controller = FloController(environment: dependencies.environment)

        await controller.bootstrap()
        controller.saveProviderCredential("openrouter_saved_1", for: .openrouter)

        #expect(dependencies.providerCredentialStore.credentialPools["openrouter"] == ["openrouter_saved_1"])
        #expect(controller.isAuthenticated == true)
        #expect(controller.providerCredentialSourceLabel(for: .openrouter) == "Saved in app keychain")
    }

    @Test
    @MainActor
    func providerRoutingOverridesAffectControllerOrderAndPolicy() {
        let configuration = FloConfiguration.loadFromEnvironment([
            "FLO_AI_PROVIDER_ORDER": "openai,gemini",
            "FLO_OPENAI_API_KEY": "openai_key_1",
            "FLO_GEMINI_API_KEY": "gemini_key_1",
            "FLO_CHATGPT_OAUTH_ENABLED": "false"
        ])
        let dependencies = TestDependencies(configuration: configuration)
        let controller = FloController(environment: dependencies.environment)

        #expect(controller.configuredProviderOrder.prefix(2) == [.openai, .gemini])
        #expect(controller.failoverAllowCrossProviderFallback == true)

        controller.moveProviderDownInFailoverOrder(.openai)
        #expect(controller.configuredProviderOrder.prefix(2) == [.gemini, .openai])

        controller.setProviderEnabledInFailover(.openai, enabled: false)
        #expect(controller.providerEnabledForFailover(.openai) == false)
        #expect(controller.providerEnabledForFailover(.gemini) == true)

        controller.setFailoverAllowCrossProviderFallback(false)
        controller.setFailoverMaxAttempts(5)
        controller.setFailoverFailureThreshold(3)
        controller.setFailoverCooldownSeconds(45)

        #expect(controller.failoverAllowCrossProviderFallback == false)
        #expect(controller.failoverMaxAttempts == 5)
        #expect(controller.failoverFailureThreshold == 3)
        #expect(controller.failoverCooldownSeconds == 45)

        let overrides = dependencies.providerRoutingStore.overrides
        #expect(Array(overrides.providerOrder.prefix(2)) == ["gemini", "openai"])
        #expect(overrides.allowCrossProviderFallback == false)
        #expect(overrides.maxAttempts == 5)
        #expect(overrides.failureThreshold == 3)
        #expect(overrides.cooldownSeconds == 45)
    }

    @Test
    @MainActor
    func saveProviderCredentialAddsProviderToFailoverRotation() async {
        let configuration = FloConfiguration.loadFromEnvironment([
            "FLO_AI_PROVIDER_ORDER": "openai",
            "FLO_OPENAI_API_KEY": "openai_key_1",
            "FLO_CHATGPT_OAUTH_ENABLED": "false"
        ])
        let dependencies = TestDependencies(configuration: configuration)
        let controller = FloController(environment: dependencies.environment)

        controller.saveProviderCredential("openrouter_saved_1", for: .openrouter)

        #expect(controller.configuredProviderOrder.contains(.openrouter))
        #expect(dependencies.providerRoutingStore.overrides.providerOrder.contains("openrouter"))
        #expect(dependencies.providerRoutingStore.overrides.allowedProviders?.contains("openrouter") == true)
    }

    @Test
    @MainActor
    func reorderProvidersInFailoverOrderPersistsCustomOrder() {
        let configuration = FloConfiguration.loadFromEnvironment([
            "FLO_AI_PROVIDER_ORDER": "openai,gemini,openrouter",
            "FLO_OPENAI_API_KEY": "openai_key_1",
            "FLO_GEMINI_API_KEY": "gemini_key_1",
            "FLO_OPENROUTER_API_KEY": "openrouter_key_1",
            "FLO_CHATGPT_OAUTH_ENABLED": "false"
        ])
        let dependencies = TestDependencies(configuration: configuration)
        let controller = FloController(environment: dependencies.environment)

        controller.reorderProvidersInFailoverOrder([.openrouter, .openai, .gemini])

        #expect(Array(controller.configuredProviderOrder.prefix(3)) == [.openrouter, .openai, .gemini])
        #expect(Array(dependencies.providerRoutingStore.overrides.providerOrder.prefix(3)) == [
            "openrouter",
            "openai",
            "gemini"
        ])
    }

    @Test
    @MainActor
    func addAndRemoveProviderFromFailoverOrderUpdatesMembership() {
        let configuration = FloConfiguration.loadFromEnvironment([
            "FLO_AI_PROVIDER_ORDER": "openai,gemini",
            "FLO_OPENAI_API_KEY": "openai_key_1",
            "FLO_GEMINI_API_KEY": "gemini_key_1",
            "FLO_CHATGPT_OAUTH_ENABLED": "false"
        ])
        let dependencies = TestDependencies(configuration: configuration)
        let controller = FloController(environment: dependencies.environment)

        controller.addProviderToFailoverOrder(.openrouter)
        #expect(controller.providerEnabledForFailover(.openrouter) == true)
        #expect(dependencies.providerRoutingStore.overrides.providerOrder.contains("openrouter"))

        controller.removeProviderFromFailoverOrder(.gemini)
        #expect(controller.providerEnabledForFailover(.gemini) == false)
        #expect(dependencies.providerRoutingStore.overrides.allowedProviders?.contains("gemini") == false)
    }

    @Test
    @MainActor
    func routingOverridePrimaryProviderChangesOAuthAvailability() {
        let configuration = makeConfiguration(oauth: sampleOAuthConfiguration(), provider: .openai, geminiApiKey: "gemini_key_1")
        let dependencies = TestDependencies(configuration: configuration)
        dependencies.providerRoutingStore.overrides = ProviderRoutingOverrides(providerOrder: ["gemini", "openai"])

        let controller = FloController(environment: dependencies.environment)

        #expect(controller.authProviderDisplayName == "Gemini")
        #expect(controller.activeProviderSupportsOAuth == false)
        #expect(controller.canAttemptLogin == false)
    }

    @Test
    @MainActor
    func removeSavedProviderCredentialReturnsGeminiToMissingKeyState() async {
        let configuration = makeConfiguration(oauth: nil, provider: .gemini, geminiApiKey: nil)
        let dependencies = TestDependencies(configuration: configuration)
        dependencies.providerCredentialStore.credentials["gemini"] = "gemini_saved_123"

        let controller = FloController(environment: dependencies.environment)
        await controller.bootstrap()

        await controller.removeSavedProviderCredential()

        #expect(dependencies.providerCredentialStore.credential(for: "gemini") == nil)
        switch controller.authState {
        case .authError:
            break
        default:
            Issue.record("Expected authError after removing Gemini key")
        }
    }

    @Test
    @MainActor
    func readSelectedWithoutTextSurfacesExplicitError() async {
        let dependencies = TestDependencies(configuration: makeConfiguration(oauth: sampleOAuthConfiguration()))
        dependencies.authService.restoredSession = sampleSession()
        dependencies.selectionReaderService.result = .failure(FloError.noSelectedText)

        let controller = FloController(environment: dependencies.environment)
        await controller.bootstrap()
        await controller.readSelectedTextFromHotkey()

        #expect(controller.statusMessage == "No selected text.")
    }

    @Test
    @MainActor
    func readSelectedRetriesTransientNoSelectionError() async {
        let dependencies = TestDependencies(configuration: makeConfiguration(oauth: sampleOAuthConfiguration()))
        dependencies.authService.restoredSession = sampleSession()
        dependencies.selectionReaderService.resultQueue = [
            .failure(FloError.noSelectedText),
            .success("hello from retry")
        ]

        let controller = FloController(environment: dependencies.environment)
        await controller.bootstrap()
        await controller.readSelectedTextFromHotkey()

        #expect(dependencies.ttsService.calls.count == 1)
        #expect(dependencies.ttsService.calls.first?.text == "hello from retry")
        #expect(controller.statusMessage == "Read-aloud completed.")
    }

    @Test
    @MainActor
    func hotkeyConflictDuringUpdateIsBlocked() {
        let dependencies = TestDependencies(configuration: makeConfiguration(oauth: sampleOAuthConfiguration()))
        let controller = FloController(environment: dependencies.environment)

        controller.updateShortcut(action: .readSelectedText, combo: DefaultShortcuts.dictation.combo)

        #expect(controller.statusMessage?.contains("Shortcut conflict") == true)
    }

    @Test
    @MainActor
    func onboardingHotkeyConfirmationPersists() {
        let dependencies = TestDependencies(configuration: makeConfiguration(oauth: sampleOAuthConfiguration()))
        let controller = FloController(environment: dependencies.environment)

        #expect(controller.onboardingHotkeyConfirmed == false)
        controller.completeHotkeyConfirmation()
        #expect(controller.onboardingHotkeyConfirmed == true)
        #expect(dependencies.onboardingStateStore.completed == true)
    }

    @Test
    @MainActor
    func voicePreferenceChangesPersist() {
        let dependencies = TestDependencies(configuration: makeConfiguration(oauth: sampleOAuthConfiguration()))
        let controller = FloController(environment: dependencies.environment)

        controller.updateVoice("nova")
        controller.updateVoiceSpeed(1.25)

        #expect(controller.voicePreferences.voice == "nova")
        #expect(controller.voicePreferences.speed == 1.25)
        #expect(dependencies.voicePreferencesStore.current.voice == "nova")
        #expect(dependencies.voicePreferencesStore.current.speed == 1.25)
    }

    @Test
    @MainActor
    func voicePreviewUsesSelectedVoiceAndSpeed() async {
        let dependencies = TestDependencies(configuration: makeConfiguration(oauth: sampleOAuthConfiguration()))
        dependencies.authService.restoredSession = sampleSession()
        let controller = FloController(environment: dependencies.environment)

        await controller.bootstrap()
        controller.updateVoice("nova")
        controller.updateVoiceSpeed(1.35)
        await controller.previewCurrentVoice()

        #expect(dependencies.ttsService.calls.count == 1)
        #expect(dependencies.ttsService.calls.first?.voice == "nova")
        #expect(dependencies.ttsService.calls.first?.speed == 1.35)
        #expect(controller.statusMessage == "Voice preview completed.")
    }

    @Test
    @MainActor
    func voicePreviewRequiresAuthentication() async {
        let dependencies = TestDependencies(configuration: makeConfiguration(oauth: sampleOAuthConfiguration()))
        let controller = FloController(environment: dependencies.environment)

        await controller.previewCurrentVoice()

        #expect(dependencies.ttsService.calls.isEmpty)
        #expect(controller.statusMessage == "You are not authenticated.")
    }

    @Test
    @MainActor
    func dictationInjectionFailureFallsBackToClipboardMessage() async {
        let dependencies = TestDependencies(configuration: makeConfiguration(oauth: sampleOAuthConfiguration()))
        dependencies.authService.restoredSession = sampleSession()
        dependencies.textInjectionService.error = FloError.injectionFailed

        let controller = FloController(environment: dependencies.environment)
        await controller.bootstrap()
        await controller.startDictationFromHotkey()
        await controller.stopDictationFromHotkey()

        #expect(controller.statusMessage?.contains("Could not inject into focused app.") == true)
    }

    @Test
    @MainActor
    func dictationSuccessCopiesTranscriptToClipboardForRecovery() async {
        setSystemClipboardText("seed")

        let dependencies = TestDependencies(configuration: makeConfiguration(oauth: sampleOAuthConfiguration()))
        dependencies.authService.restoredSession = sampleSession()

        let controller = FloController(environment: dependencies.environment)
        await controller.bootstrap()
        await controller.startDictationFromHotkey()
        await controller.stopDictationFromHotkey()

        #expect(controller.statusMessage?.contains("Transcript copied to clipboard.") == true)
        #expect(systemClipboardText() == "mock")
    }

    @Test
    @MainActor
    func dictationPermissionFailureAfterTranscriptionStillCopiesTranscript() async {
        setSystemClipboardText("seed")

        let dependencies = TestDependencies(configuration: makeConfiguration(oauth: sampleOAuthConfiguration()))
        dependencies.authService.restoredSession = sampleSession()
        dependencies.permissionsService.status = PermissionStatus(
            microphone: .granted,
            accessibility: .denied,
            inputMonitoring: .granted
        )

        let controller = FloController(environment: dependencies.environment)
        await controller.bootstrap()
        await controller.startDictationFromHotkey()
        await controller.stopDictationFromHotkey()

        #expect(controller.statusMessage?.contains("Permission denied: Accessibility.") == true)
        #expect(controller.statusMessage?.contains("Transcript copied to clipboard.") == true)
        #expect(systemClipboardText() == "mock")
        #expect(controller.historyEntries.first?.success == false)
        #expect(controller.historyEntries.first?.inputText == "mock")
    }

    @Test
    @MainActor
    func pasteLastTranscriptInsertsMostRecentDictation() async {
        let dependencies = TestDependencies(configuration: makeConfiguration(oauth: sampleOAuthConfiguration()))
        dependencies.authService.restoredSession = sampleSession()

        let controller = FloController(environment: dependencies.environment)
        await controller.bootstrap()
        await controller.startDictationFromHotkey()
        await controller.stopDictationFromHotkey()

        dependencies.textInjectionService.injectedTexts.removeAll()
        controller.pasteLastTranscript()

        #expect(controller.canPasteLastTranscript == true)
        #expect(controller.lastDictationTranscript == "mock")
        #expect(dependencies.textInjectionService.injectedTexts.last == "mock")
        #expect(controller.statusMessage == "Inserted last transcript.")
    }

    @Test
    @MainActor
    func pasteLastTranscriptWithoutHistoryShowsExplicitMessage() {
        let dependencies = TestDependencies(configuration: makeConfiguration(oauth: sampleOAuthConfiguration()))
        let controller = FloController(environment: dependencies.environment)

        controller.pasteLastTranscript()

        #expect(controller.canPasteLastTranscript == false)
        #expect(controller.lastDictationTranscript == nil)
        #expect(controller.statusMessage == "No transcript available yet.")
    }

    @Test
    @MainActor
    func pasteLastTranscriptFallsBackToClipboardOnInjectionFailure() async {
        setSystemClipboardText("seed")

        let dependencies = TestDependencies(configuration: makeConfiguration(oauth: sampleOAuthConfiguration()))
        dependencies.authService.restoredSession = sampleSession()

        let controller = FloController(environment: dependencies.environment)
        await controller.bootstrap()
        await controller.startDictationFromHotkey()
        await controller.stopDictationFromHotkey()

        dependencies.textInjectionService.error = FloError.injectionFailed
        controller.pasteLastTranscript()

        #expect(controller.statusMessage?.contains("Last transcript copied to clipboard.") == true)
        #expect(systemClipboardText() == "mock")
    }

    @Test
    @MainActor
    func liveDictationInjectsPartialTranscriptWhileListening() async {
        let dependencies = TestDependencies(configuration: makeConfiguration(oauth: sampleOAuthConfiguration()))
        dependencies.authService.restoredSession = sampleSession()
        dependencies.transcriptionService.text = "hello world from flo"

        let controller = FloController(environment: dependencies.environment)
        await controller.bootstrap()
        controller.setLiveDictationEnabled(true)

        await controller.startDictationFromHotkey()
        dependencies.speechCaptureService.emitPartial("hello world ")
        try? await Task.sleep(nanoseconds: 60_000_000)
        await controller.stopDictationFromHotkey()

        #expect(dependencies.textInjectionService.injectedTexts.contains("hello world "))
        #expect(dependencies.textInjectionService.injectedTexts.contains("from flo"))
        #expect(controller.statusMessage?.contains("Live dictation completed.") == true)
    }

    @Test
    @MainActor
    func dictationRewriteAppliesBeforeFinalInjection() async {
        let dependencies = TestDependencies(configuration: makeConfiguration(oauth: sampleOAuthConfiguration()))
        dependencies.authService.restoredSession = sampleSession()
        dependencies.transcriptionService.text = "send this as quick notes"
        dependencies.dictationRewriteService.responseTransform = { _ in
            """
            ## Quick Notes
            - Send this update now.
            """
        }

        let controller = FloController(environment: dependencies.environment)
        await controller.bootstrap()
        controller.setDictationRewriteEnabled(true)

        await controller.startDictationFromHotkey()
        await controller.stopDictationFromHotkey()

        #expect(dependencies.textInjectionService.injectedTexts.last?.contains("## Quick Notes") == true)
        #expect(controller.historyEntries.first?.inputText == "send this as quick notes")
        #expect(controller.historyEntries.first?.outputText?.contains("## Quick Notes") == true)
    }

    @Test
    @MainActor
    func liveDictationReplaceModeOverwritesLiveDraftWithFinalText() async {
        let dependencies = TestDependencies(configuration: makeConfiguration(oauth: sampleOAuthConfiguration()))
        dependencies.authService.restoredSession = sampleSession()
        dependencies.transcriptionService.text = "please send this to the team right now"
        dependencies.dictationRewriteService.responseTransform = { _ in
            "Please send this update to the team immediately."
        }

        let controller = FloController(environment: dependencies.environment)
        await controller.bootstrap()
        controller.setLiveDictationEnabled(true)
        controller.setDictationLiveFinalizationMode(.replaceWithFinal)

        await controller.startDictationFromHotkey()
        dependencies.speechCaptureService.emitPartial("please send this ")
        try? await Task.sleep(nanoseconds: 60_000_000)
        await controller.stopDictationFromHotkey()

        #expect(dependencies.textInjectionService.replaceCalls.count == 1)
        #expect(dependencies.textInjectionService.replaceCalls.first?.previousText == "please send this ")
        #expect(dependencies.textInjectionService.replaceCalls.first?.updatedText == "Please send this update to the team immediately.")
        #expect(controller.statusMessage?.contains("Replaced live draft with final transcript.") == true)
    }

    @Test
    @MainActor
    func liveDictationFallsBackWhenProviderTranscriptionFails() async {
        let dependencies = TestDependencies(configuration: makeConfiguration(oauth: sampleOAuthConfiguration()))
        dependencies.authService.restoredSession = sampleSession()
        dependencies.transcriptionService.error = FloError.network("Gemini returned a non-transcription response.")

        let controller = FloController(environment: dependencies.environment)
        await controller.bootstrap()
        controller.setLiveDictationEnabled(true)

        await controller.startDictationFromHotkey()
        dependencies.speechCaptureService.emitPartial("live fallback transcript ")
        try? await Task.sleep(nanoseconds: 60_000_000)
        await controller.stopDictationFromHotkey()

        #expect(controller.statusMessage?.contains("used live transcript fallback") == true)
        #expect(controller.historyEntries.first?.inputText == "live fallback transcript")
        #expect(controller.historyEntries.first?.success == true)
    }

    @Test
    @MainActor
    func dictationPresetAppliesProfileWithoutOverwritingLiveControls() {
        let dependencies = TestDependencies(configuration: makeConfiguration(oauth: sampleOAuthConfiguration()))
        let controller = FloController(environment: dependencies.environment)

        controller.setLiveDictationEnabled(true)
        controller.setDictationLiveFinalizationMode(.replaceWithFinal)
        controller.setDictationCustomInstructions("Keep action items explicit.")
        controller.applyDictationRewritePreset(.professional)

        #expect(controller.dictationRewritePreferences.baseTone == .professional)
        #expect(controller.dictationRewritePreferences.warmth == .less)
        #expect(controller.dictationRewritePreferences.enthusiasm == .less)
        #expect(controller.dictationRewritePreferences.headersAndLists == .more)
        #expect(controller.dictationRewritePreferences.emoji == .less)
        #expect(controller.dictationRewritePreferences.liveTypingEnabled == true)
        #expect(controller.dictationRewritePreferences.liveFinalizationMode == .replaceWithFinal)
        #expect(controller.dictationRewritePreferences.customInstructions == "Keep action items explicit.")
    }

    @Test
    @MainActor
    func floatingBarReadActionCancelsNarrationWhenSpeaking() async {
        let dependencies = TestDependencies(configuration: makeConfiguration(oauth: sampleOAuthConfiguration()))
        dependencies.authService.restoredSession = sampleSession()
        dependencies.ttsService.blocksUntilStopped = true
        dependencies.selectionReaderService.result = .success("Cancel me midway")

        let controller = FloController(environment: dependencies.environment)
        await controller.bootstrap()

        let speakingTask = Task { @MainActor in
            await controller.readSelectedTextFromHotkey()
        }

        try? await Task.sleep(nanoseconds: 80_000_000)
        dependencies.floatingBarManager.actions?.triggerReadSelected()
        try? await Task.sleep(nanoseconds: 80_000_000)
        await speakingTask.value

        #expect(dependencies.ttsService.stopCalls == 1)
        #expect(controller.recorderState == .idle)
        #expect(controller.statusMessage == "Read-aloud canceled.")
    }
}

@MainActor
private final class TestDependencies {
    let authService = MockAuthService()
    let shortcutStore = MockShortcutStore()
    let hotkeyManager = MockHotkeyManager()
    let speechCaptureService = MockSpeechCaptureService()
    let transcriptionService = MockTranscriptionService()
    let selectionReaderService = MockSelectionReaderService()
    let textInjectionService = MockTextInjectionService()
    let ttsService = MockTTSService()
    let historyStore = MockHistoryStore()
    let dictationRewriteService = MockDictationRewriteService()
    let providerCredentialStore = MockProviderCredentialStore()
    let providerRoutingStore = MockProviderRoutingStore()
    let dictationRewritePreferencesStore = MockDictationRewritePreferencesStore()
    let voicePreferencesStore = MockVoicePreferencesStore()
    let onboardingStateStore = MockOnboardingStateStore()
    let permissionsService = MockPermissionsService()
    let floatingBarManager = MockFloatingBarManager()
    let logger = MockLogger()

    let environment: AppEnvironment

    init(configuration: FloConfiguration) {
        UserDefaults.standard.removeObject(forKey: "flo.live_dictation_enabled")
        self.environment = AppEnvironment(
            configuration: configuration,
            authService: authService,
            shortcutStore: shortcutStore,
            hotkeyManager: hotkeyManager,
            speechCaptureService: speechCaptureService,
            transcriptionService: transcriptionService,
            selectionReaderService: selectionReaderService,
            textInjectionService: textInjectionService,
            ttsService: ttsService,
            historyStore: historyStore,
            dictationRewriteService: dictationRewriteService,
            providerCredentialStore: providerCredentialStore,
            providerRoutingStore: providerRoutingStore,
            dictationRewritePreferencesStore: dictationRewritePreferencesStore,
            voicePreferencesStore: voicePreferencesStore,
            onboardingStateStore: onboardingStateStore,
            permissionsService: permissionsService,
            floatingBarManager: floatingBarManager,
            logger: logger
        )
    }
}

@MainActor
private final class MockAuthService: AuthService {
    var restoredSession: UserSession?

    func restoreSession() async -> UserSession? {
        restoredSession
    }

    func startOAuth() async throws -> UserSession {
        restoredSession ?? sampleSession()
    }

    func refreshSession(_ session: UserSession) async throws -> UserSession {
        session
    }

    func logout() async {}
}

private final class MockShortcutStore: ShortcutStore {
    var bindings: [ShortcutBinding] = DefaultShortcuts.all

    func loadBindings() -> [ShortcutBinding] {
        bindings
    }

    func saveBindings(_ bindings: [ShortcutBinding]) {
        self.bindings = bindings
    }
}

private final class MockHotkeyManager: HotkeyManaging {
    func start(bindings: [ShortcutBinding], handlers: HotkeyHandlers) {}
    func stop() {}
}

private final class MockSpeechCaptureService: SpeechCaptureService {
    var transcriptHandler: ((String) -> Void)?

    func startCapture(levelHandler: @escaping (Float) -> Void) throws {
        transcriptHandler = nil
    }

    func startCapture(
        levelHandler: @escaping (Float) -> Void,
        transcriptHandler: @escaping (String) -> Void
    ) throws {
        self.transcriptHandler = transcriptHandler
    }

    func stopCapture() throws -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("mock-audio")
            .appendingPathExtension("wav")
    }

    func cancelCapture() {}

    func emitPartial(_ partial: String) {
        transcriptHandler?(partial)
    }
}

private final class MockTranscriptionService: TranscriptionService, @unchecked Sendable {
    var text = "mock"
    var error: Error?

    func transcribe(audioFileURL: URL, authToken: String) async throws -> TranscriptResult {
        if let error {
            throw error
        }
        return TranscriptResult(text: text, requestID: "req_mock", latencyMs: 120, confidence: 0.8)
    }
}

private final class MockSelectionReaderService: SelectionReaderService {
    var result: Result<String, Error> = .success("hello world")
    var resultQueue: [Result<String, Error>] = []

    func getSelectedText() throws -> String {
        if !resultQueue.isEmpty {
            let next = resultQueue.removeFirst()
            switch next {
            case .success(let value):
                return value
            case .failure(let error):
                throw error
            }
        }

        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        }
    }
}

private final class MockTextInjectionService: TextInjectionService {
    struct ReplaceCall {
        let previousText: String
        let updatedText: String
    }

    var error: Error?
    var injectedTexts: [String] = []
    var replaceCalls: [ReplaceCall] = []

    func inject(text: String) throws {
        injectedTexts.append(text)
        if let error {
            throw error
        }
    }

    func replaceRecentText(previousText: String, with updatedText: String) throws {
        replaceCalls.append(ReplaceCall(previousText: previousText, updatedText: updatedText))
        if let error {
            throw error
        }
    }
}

@MainActor
private final class MockTTSService: TTSService {
    struct Call: Sendable {
        let text: String
        let authToken: String
        let voice: String
        let speed: Double
    }

    var calls: [Call] = []
    var error: Error?
    var blocksUntilStopped = false
    var stopCalls = 0
    private var blockedContinuation: CheckedContinuation<Void, Error>?

    func synthesizeAndPlay(text: String, authToken: String, voice: String, speed: Double) async throws {
        calls.append(Call(text: text, authToken: authToken, voice: voice, speed: speed))
        if let error {
            throw error
        }
        if blocksUntilStopped {
            try await withCheckedThrowingContinuation { continuation in
                blockedContinuation = continuation
            }
        }
    }

    func stopPlayback() {
        stopCalls += 1
        blockedContinuation?.resume(throwing: CancellationError())
        blockedContinuation = nil
    }
}

private final class MockHistoryStore: SessionHistoryStore {
    private var entries: [HistoryEntry] = []

    func load() throws -> [HistoryEntry] {
        entries
    }

    func append(_ entry: HistoryEntry) throws {
        entries.insert(entry, at: 0)
    }

    func clear() throws {
        entries = []
    }
}

private final class MockDictationRewriteService: DictationRewriteService, @unchecked Sendable {
    var responseTransform: (String) -> String = { $0 }
    var error: Error?

    func rewrite(
        transcript: String,
        authToken: String,
        preferences: DictationRewritePreferences
    ) async throws -> String {
        _ = authToken
        _ = preferences
        if let error {
            throw error
        }
        return responseTransform(transcript)
    }
}

private final class MockProviderCredentialStore: ProviderCredentialStore {
    var credentials: [String: String] = [:]
    var credentialPools: [String: [String]] = [:]

    func credential(for providerID: String) -> String? {
        credentialPools[providerID]?.first ?? credentials[providerID]
    }

    func credentials(for providerID: String) -> [String] {
        if let pool = credentialPools[providerID] {
            return pool
        }
        if let value = credentials[providerID] {
            return [value]
        }
        return []
    }

    func saveCredential(_ credential: String, for providerID: String) throws {
        credentials[providerID] = credential
        credentialPools[providerID] = [credential]
    }

    func saveCredentials(_ credentials: [String], for providerID: String) throws {
        let normalized = credentials
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if normalized.isEmpty {
            try clearCredential(for: providerID)
            return
        }

        self.credentials[providerID] = normalized[0]
        credentialPools[providerID] = normalized
    }

    func clearCredential(for providerID: String) throws {
        credentials.removeValue(forKey: providerID)
        credentialPools.removeValue(forKey: providerID)
    }
}

private final class MockProviderRoutingStore: ProviderRoutingStore {
    var overrides: ProviderRoutingOverrides = .default

    func loadOverrides() -> ProviderRoutingOverrides {
        overrides
    }

    func saveOverrides(_ overrides: ProviderRoutingOverrides) {
        self.overrides = overrides
    }
}

private final class MockDictationRewritePreferencesStore: DictationRewritePreferencesStore {
    var current: DictationRewritePreferences = .default

    func load() -> DictationRewritePreferences {
        current
    }

    func save(_ preferences: DictationRewritePreferences) {
        current = preferences
    }
}

private final class MockVoicePreferencesStore: VoicePreferencesStore {
    var current = VoicePreferences(voice: "alloy", speed: 1.0)

    func load() -> VoicePreferences {
        current
    }

    func save(_ preferences: VoicePreferences) {
        current = preferences
    }
}

private final class MockOnboardingStateStore: OnboardingStateStore {
    var completed = false

    func hasCompletedHotkeyConfirmation() -> Bool {
        completed
    }

    func setHotkeyConfirmationCompleted(_ completed: Bool) {
        self.completed = completed
    }
}

@MainActor
private final class MockPermissionsService: PermissionsService {
    var status = PermissionStatus(microphone: .granted, accessibility: .granted, inputMonitoring: .granted)

    func refreshStatus() -> PermissionStatus {
        status
    }

    func requestMicrophoneAccess() async -> Bool {
        true
    }

    func openSystemSettings(for permission: PermissionKind) {}
}

@MainActor
private final class MockFloatingBarManager: FloatingBarManaging {
    var actions: FloatingBarActions?

    func setActions(_ actions: FloatingBarActions?) {
        self.actions = actions
    }

    func show(state: RecorderState) {}
    func update(state: RecorderState) {}
    func updateAudioLevel(_ level: Float) {}
    func hide() {}
}

private final class MockLogger: AppLogger {
    func info(_ message: String) {}
    func error(_ message: String) {}
}

private func makeConfiguration(
    oauth: OAuthConfiguration?,
    provider: AIProvider = .openai,
    geminiApiKey: String? = nil
) -> FloConfiguration {
    FloConfiguration(
        provider: provider,
        transcriptionURL: URL(string: "https://api.openai.com/v1/audio/transcriptions")!,
        ttsURL: URL(string: "https://api.openai.com/v1/audio/speech")!,
        rewriteURL: URL(string: "https://api.openai.com/v1/chat/completions")!,
        openAIApiKey: nil,
        geminiApiKey: geminiApiKey,
        transcriptionModel: "gpt-4o-mini-transcribe",
        ttsModel: "gpt-4o-mini-tts",
        rewriteModel: "gpt-4o-mini",
        ttsVoice: "alloy",
        ttsSpeed: 1.0,
        maxTTSCharactersPerChunk: 1500,
        retainAudioDebugArtifacts: false,
        hostAllowlist: ["api.openai.com"],
        featureFlags: .allEnabled,
        manualUpdateURL: nil,
        oauth: oauth
    )
}

private func sampleOAuthConfiguration() -> OAuthConfiguration {
    OAuthConfiguration(
        authorizeURL: URL(string: "https://auth.example.com/oauth/authorize")!,
        tokenURL: URL(string: "https://auth.example.com/oauth/token")!,
        clientID: "client_id",
        redirectURI: "flo://oauth/callback",
        scopes: "openid profile email"
    )
}

private func sampleSession() -> UserSession {
    UserSession(
        accessToken: "token",
        refreshToken: "refresh",
        tokenType: "Bearer",
        expiresAt: Date().addingTimeInterval(3600)
    )
}

@MainActor
private func setSystemClipboardText(_ text: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    _ = pasteboard.setString(text, forType: .string)
}

@MainActor
private func systemClipboardText() -> String? {
    NSPasteboard.general.string(forType: .string)
}
