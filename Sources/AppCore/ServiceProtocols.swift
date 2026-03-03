import Foundation

@MainActor
public protocol AuthService: AnyObject {
    func restoreSession() async -> UserSession?
    func startOAuth() async throws -> UserSession
    func refreshSession(_ session: UserSession) async throws -> UserSession
    func logout() async
}

public protocol ShortcutStore: AnyObject {
    func loadBindings() -> [ShortcutBinding]
    func saveBindings(_ bindings: [ShortcutBinding])
}

public protocol HotkeyManaging: AnyObject {
    func start(bindings: [ShortcutBinding], handlers: HotkeyHandlers)
    func stop()
}

public protocol SpeechCaptureService: AnyObject {
    func startCapture(levelHandler: @escaping (Float) -> Void) throws
    func startCapture(
        levelHandler: @escaping (Float) -> Void,
        transcriptHandler: @escaping (String) -> Void
    ) throws
    func stopCapture() throws -> URL
    func cancelCapture()
}

public protocol TranscriptionService: AnyObject, Sendable {
    func transcribe(audioFileURL: URL, authToken: String) async throws -> TranscriptResult
}

public protocol SelectionReaderService: AnyObject {
    func getSelectedText() throws -> String
}

public protocol TextInjectionService: AnyObject {
    func inject(text: String) throws
    func replaceRecentText(previousText: String, with updatedText: String) throws
}

@MainActor
public protocol TTSService: AnyObject {
    func synthesizeAndPlay(text: String, authToken: String, voice: String, speed: Double) async throws
    func stopPlayback()
}

public protocol SessionHistoryStore: AnyObject {
    func load() throws -> [HistoryEntry]
    func append(_ entry: HistoryEntry) throws
    func clear() throws
}

public protocol DictationRewriteService: AnyObject, Sendable {
    func rewrite(
        transcript: String,
        authToken: String,
        preferences: DictationRewritePreferences
    ) async throws -> String
}

public protocol ProviderCredentialStore: AnyObject {
    func credential(for providerID: String) -> String?
    func saveCredential(_ credential: String, for providerID: String) throws
    func clearCredential(for providerID: String) throws
    func credentials(for providerID: String) -> [String]
    func saveCredentials(_ credentials: [String], for providerID: String) throws
}

public struct ProviderRoutingOverrides: Codable, Equatable, Sendable {
    public let providerOrder: [String]
    public let allowCrossProviderFallback: Bool?
    public let maxAttempts: Int?
    public let failureThreshold: Int?
    public let cooldownSeconds: Int?
    public let allowedProviders: [String]?

    public init(
        providerOrder: [String] = [],
        allowCrossProviderFallback: Bool? = nil,
        maxAttempts: Int? = nil,
        failureThreshold: Int? = nil,
        cooldownSeconds: Int? = nil,
        allowedProviders: [String]? = nil
    ) {
        self.providerOrder = providerOrder
        self.allowCrossProviderFallback = allowCrossProviderFallback
        self.maxAttempts = maxAttempts
        self.failureThreshold = failureThreshold
        self.cooldownSeconds = cooldownSeconds
        self.allowedProviders = allowedProviders
    }

    public static let `default` = ProviderRoutingOverrides()
}

public protocol ProviderRoutingStore: AnyObject {
    func loadOverrides() -> ProviderRoutingOverrides
    func saveOverrides(_ overrides: ProviderRoutingOverrides)
}

public protocol DictationRewritePreferencesStore: AnyObject {
    func load() -> DictationRewritePreferences
    func save(_ preferences: DictationRewritePreferences)
}

public protocol VoicePreferencesStore: AnyObject {
    func load() -> VoicePreferences
    func save(_ preferences: VoicePreferences)
}

public protocol OnboardingStateStore: AnyObject {
    func hasCompletedHotkeyConfirmation() -> Bool
    func setHotkeyConfirmationCompleted(_ completed: Bool)
}

public protocol AppLogger: AnyObject {
    func info(_ message: String)
    func error(_ message: String)
}

public enum PermissionKind: String, CaseIterable, Sendable {
    case microphone
    case accessibility
    case inputMonitoring
}

@MainActor
public protocol PermissionsService: AnyObject {
    func refreshStatus() -> PermissionStatus
    func requestMicrophoneAccess() async -> Bool
    func openSystemSettings(for permission: PermissionKind)
}

public protocol FloatingBarManaging: AnyObject {
    @MainActor func setActions(_ actions: FloatingBarActions?)
    @MainActor func show(state: RecorderState)
    @MainActor func update(state: RecorderState)
    @MainActor func updateAudioLevel(_ level: Float)
    @MainActor func hide()
}

public struct FloatingBarActions {
    public let toggleDictation: () -> Void
    public let triggerReadSelected: () -> Void
    public let openMainWindow: () -> Void
    public let dictationHint: String
    public let readSelectedHint: String

    public init(
        toggleDictation: @escaping () -> Void,
        triggerReadSelected: @escaping () -> Void,
        openMainWindow: @escaping () -> Void,
        dictationHint: String = "Hold your dictation shortcut to start dictating, or click to toggle.",
        readSelectedHint: String = "Read selected text aloud."
    ) {
        self.toggleDictation = toggleDictation
        self.triggerReadSelected = triggerReadSelected
        self.openMainWindow = openMainWindow
        self.dictationHint = dictationHint
        self.readSelectedHint = readSelectedHint
    }
}

public extension FloatingBarManaging {
    @MainActor func setActions(_ actions: FloatingBarActions?) {}
    @MainActor func updateAudioLevel(_ level: Float) {}
}

public extension SpeechCaptureService {
    func startCapture(
        levelHandler: @escaping (Float) -> Void,
        transcriptHandler: @escaping (String) -> Void
    ) throws {
        _ = transcriptHandler
        try startCapture(levelHandler: levelHandler)
    }
}

public extension TextInjectionService {
    func replaceRecentText(previousText: String, with updatedText: String) throws {
        if updatedText.hasPrefix(previousText) {
            let suffix = String(updatedText.dropFirst(previousText.count))
            if !suffix.isEmpty {
                try inject(text: suffix)
            }
            return
        }

        if !updatedText.isEmpty {
            try inject(text: updatedText)
        }
    }
}

public extension PermissionsService {
    func openSystemSettings(for permission: PermissionKind) {}
}

public extension TTSService {
    func stopPlayback() {}
}

public extension ProviderCredentialStore {
    func credentials(for providerID: String) -> [String] {
        guard let value = credential(for: providerID)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else {
            return []
        }
        return [value]
    }

    func saveCredentials(_ credentials: [String], for providerID: String) throws {
        let normalized = credentials
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let first = normalized.first else {
            try clearCredential(for: providerID)
            return
        }
        try saveCredential(first, for: providerID)
    }
}
