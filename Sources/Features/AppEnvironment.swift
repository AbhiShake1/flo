import AppCore
import Foundation
import Infrastructure

public struct AppEnvironment {
    public let configuration: FloConfiguration
    public let authService: AuthService
    public let shortcutStore: ShortcutStore
    public let hotkeyManager: HotkeyManaging
    public let speechCaptureService: SpeechCaptureService
    public let transcriptionService: TranscriptionService
    public let selectionReaderService: SelectionReaderService
    public let textInjectionService: TextInjectionService
    public let ttsService: TTSService
    public let historyStore: SessionHistoryStore
    public let dictationRewriteService: DictationRewriteService
    public let providerCredentialStore: ProviderCredentialStore
    public let dictationRewritePreferencesStore: DictationRewritePreferencesStore
    public let voicePreferencesStore: VoicePreferencesStore
    public let onboardingStateStore: OnboardingStateStore
    public let permissionsService: PermissionsService
    public let floatingBarManager: FloatingBarManaging
    public let logger: AppLogger

    public init(
        configuration: FloConfiguration,
        authService: AuthService,
        shortcutStore: ShortcutStore,
        hotkeyManager: HotkeyManaging,
        speechCaptureService: SpeechCaptureService,
        transcriptionService: TranscriptionService,
        selectionReaderService: SelectionReaderService,
        textInjectionService: TextInjectionService,
        ttsService: TTSService,
        historyStore: SessionHistoryStore,
        dictationRewriteService: DictationRewriteService,
        providerCredentialStore: ProviderCredentialStore,
        dictationRewritePreferencesStore: DictationRewritePreferencesStore,
        voicePreferencesStore: VoicePreferencesStore,
        onboardingStateStore: OnboardingStateStore,
        permissionsService: PermissionsService,
        floatingBarManager: FloatingBarManaging,
        logger: AppLogger
    ) {
        self.configuration = configuration
        self.authService = authService
        self.shortcutStore = shortcutStore
        self.hotkeyManager = hotkeyManager
        self.speechCaptureService = speechCaptureService
        self.transcriptionService = transcriptionService
        self.selectionReaderService = selectionReaderService
        self.textInjectionService = textInjectionService
        self.ttsService = ttsService
        self.historyStore = historyStore
        self.dictationRewriteService = dictationRewriteService
        self.providerCredentialStore = providerCredentialStore
        self.dictationRewritePreferencesStore = dictationRewritePreferencesStore
        self.voicePreferencesStore = voicePreferencesStore
        self.onboardingStateStore = onboardingStateStore
        self.permissionsService = permissionsService
        self.floatingBarManager = floatingBarManager
        self.logger = logger
    }
}

public extension AppEnvironment {
    @MainActor
    static func live(
        configuration: FloConfiguration = .loadFromEnvironment(LocalEnvLoader.mergedEnvironment()),
        floatingBarEnabled: Bool = true
    ) -> AppEnvironment {
        let floatingBarManager: FloatingBarManaging = floatingBarEnabled ? FloatingBarWindowManager() : NoopFloatingBarManager()
        let transcriptionService: TranscriptionService
        let ttsService: TTSService
        let dictationRewriteService: DictationRewriteService

        switch configuration.provider {
        case .openai:
            transcriptionService = OpenAITranscriptionService(configuration: configuration)
            ttsService = OpenAITTSService(configuration: configuration)
            dictationRewriteService = NoopDictationRewriteService()
        case .gemini:
            transcriptionService = GeminiTranscriptionService(configuration: configuration)
            ttsService = GeminiTTSService(configuration: configuration)
            dictationRewriteService = GeminiDictationRewriteService(configuration: configuration)
        }

        return AppEnvironment(
            configuration: configuration,
            authService: ChatGPTOAuthService(configuration: configuration.oauth),
            shortcutStore: UserDefaultsShortcutStore(),
            hotkeyManager: GlobalHotkeyManager(),
            speechCaptureService: AVAudioEngineCaptureService(),
            transcriptionService: transcriptionService,
            selectionReaderService: MacSelectionReaderService(),
            textInjectionService: SmartPasteTextInjectionService(),
            ttsService: ttsService,
            historyStore: SecureSessionHistoryStore(),
            dictationRewriteService: dictationRewriteService,
            providerCredentialStore: KeychainProviderCredentialStore(),
            dictationRewritePreferencesStore: UserDefaultsDictationRewritePreferencesStore(),
            voicePreferencesStore: UserDefaultsVoicePreferencesStore(
                fallback: VoicePreferences(voice: configuration.ttsVoice, speed: configuration.ttsSpeed)
            ),
            onboardingStateStore: UserDefaultsOnboardingStateStore(),
            permissionsService: MacPermissionsService(),
            floatingBarManager: floatingBarManager,
            logger: RedactingAppLogger()
        )
    }
}
