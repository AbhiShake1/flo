import Foundation

public struct UserSession: Codable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let tokenType: String
    public let expiresAt: Date
    public let accountID: String?

    public init(
        accessToken: String,
        refreshToken: String?,
        tokenType: String,
        expiresAt: Date,
        accountID: String? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenType = tokenType
        self.expiresAt = expiresAt
        self.accountID = accountID
    }

    public var isExpired: Bool {
        Date() >= expiresAt
    }
}

public enum AuthState: Equatable, Sendable {
    case loggedOut
    case authenticating
    case loggedIn(UserSession)
    case authError(String)
}

public enum ShortcutAction: String, Codable, CaseIterable, Sendable {
    case dictationHold
    case readSelectedText
    case pushToTalkToggle

    public var displayName: String {
        switch self {
        case .dictationHold:
            return "Dictation Hold"
        case .readSelectedText:
            return "Read Selected Text"
        case .pushToTalkToggle:
            return "Push-To-Talk (Reserved)"
        }
    }
}

public struct ShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    public static let command = ShortcutModifiers(rawValue: 1 << 0)
    public static let option = ShortcutModifiers(rawValue: 1 << 1)
    public static let shift = ShortcutModifiers(rawValue: 1 << 2)
    public static let control = ShortcutModifiers(rawValue: 1 << 3)

    public static let none: ShortcutModifiers = []

    public var humanReadable: String {
        var pieces: [String] = []
        if contains(.command) { pieces.append("⌘") }
        if contains(.option) { pieces.append("⌥") }
        if contains(.shift) { pieces.append("⇧") }
        if contains(.control) { pieces.append("⌃") }
        return pieces.joined()
    }
}

public struct KeyCombo: Codable, Equatable, Hashable, Sendable {
    public let keyCode: UInt16
    public let modifiers: ShortcutModifiers
    public let keyDisplay: String

    public init(keyCode: UInt16, modifiers: ShortcutModifiers, keyDisplay: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyDisplay = keyDisplay
    }

    public var humanReadable: String {
        "\(modifiers.humanReadable)\(keyDisplay)"
    }
}

public struct ShortcutBinding: Codable, Equatable, Sendable {
    public let action: ShortcutAction
    public var combo: KeyCombo
    public var enabled: Bool

    public init(action: ShortcutAction, combo: KeyCombo, enabled: Bool = true) {
        self.action = action
        self.combo = combo
        self.enabled = enabled
    }
}

public enum RecorderState: Equatable, Sendable {
    case idle
    case listening
    case transcribing
    case injecting
    case speaking
    case error(String)

    public var label: String {
        switch self {
        case .idle:
            return "Idle"
        case .listening:
            return "Listening"
        case .transcribing:
            return "Transcribing"
        case .injecting:
            return "Injecting"
        case .speaking:
            return "Speaking"
        case .error:
            return "Error"
        }
    }
}

public struct TranscriptResult: Codable, Equatable, Sendable {
    public let text: String
    public let requestID: String?
    public let latencyMs: Int
    public let confidence: Double?

    public init(text: String, requestID: String?, latencyMs: Int, confidence: Double?) {
        self.text = text
        self.requestID = requestID
        self.latencyMs = latencyMs
        self.confidence = confidence
    }
}

public enum HistoryEventKind: String, Codable, Sendable {
    case dictation
    case readAloud
}

public struct HistoryEntry: Codable, Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let kind: HistoryEventKind
    public let inputText: String
    public let outputText: String?
    public let requestID: String?
    public let latencyMs: Int?
    public let success: Bool
    public let errorMessage: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        kind: HistoryEventKind,
        inputText: String,
        outputText: String?,
        requestID: String? = nil,
        latencyMs: Int? = nil,
        success: Bool,
        errorMessage: String?
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.inputText = inputText
        self.outputText = outputText
        self.requestID = requestID
        self.latencyMs = latencyMs
        self.success = success
        self.errorMessage = errorMessage
    }
}

public struct VoicePreferences: Codable, Equatable, Sendable {
    public let voice: String
    public let speed: Double

    public init(voice: String, speed: Double) {
        self.voice = voice
        self.speed = speed
    }
}

public enum DictationBaseTone: String, Codable, CaseIterable, Sendable {
    case `default`
    case professional
    case friendly
    case candid
    case efficient
    case nerdy
    case quirky

    public var displayName: String {
        switch self {
        case .default:
            return "Default"
        case .professional:
            return "Professional"
        case .friendly:
            return "Friendly"
        case .candid:
            return "Candid"
        case .efficient:
            return "Efficient"
        case .nerdy:
            return "Nerdy"
        case .quirky:
            return "Quirky"
        }
    }
}

public enum DictationStyleLevel: String, Codable, CaseIterable, Sendable {
    case less
    case `default`
    case more

    public var displayName: String {
        switch self {
        case .less:
            return "Less"
        case .default:
            return "Default"
        case .more:
            return "More"
        }
    }
}

public enum DictationLiveFinalizationMode: String, Codable, CaseIterable, Sendable {
    case appendOnly
    case replaceWithFinal

    public var displayName: String {
        switch self {
        case .appendOnly:
            return "Append"
        case .replaceWithFinal:
            return "Replace"
        }
    }
}

public enum DictationRewritePreset: String, Codable, CaseIterable, Sendable {
    case `default`
    case professional
    case friendly
    case candid
    case efficient
    case nerdy
    case quirky

    public var displayName: String {
        switch self {
        case .default:
            return "Default"
        case .professional:
            return "Professional"
        case .friendly:
            return "Friendly"
        case .candid:
            return "Candid"
        case .efficient:
            return "Efficient"
        case .nerdy:
            return "Nerdy"
        case .quirky:
            return "Quirky"
        }
    }
}

public struct DictationRewritePreferences: Codable, Equatable, Sendable {
    public let rewriteEnabled: Bool
    public let liveTypingEnabled: Bool
    public let liveFinalizationMode: DictationLiveFinalizationMode
    public let baseTone: DictationBaseTone
    public let warmth: DictationStyleLevel
    public let enthusiasm: DictationStyleLevel
    public let headersAndLists: DictationStyleLevel
    public let emoji: DictationStyleLevel
    public let customInstructions: String

    public init(
        rewriteEnabled: Bool,
        liveTypingEnabled: Bool,
        liveFinalizationMode: DictationLiveFinalizationMode,
        baseTone: DictationBaseTone,
        warmth: DictationStyleLevel,
        enthusiasm: DictationStyleLevel,
        headersAndLists: DictationStyleLevel,
        emoji: DictationStyleLevel,
        customInstructions: String
    ) {
        self.rewriteEnabled = rewriteEnabled
        self.liveTypingEnabled = liveTypingEnabled
        self.liveFinalizationMode = liveFinalizationMode
        self.baseTone = baseTone
        self.warmth = warmth
        self.enthusiasm = enthusiasm
        self.headersAndLists = headersAndLists
        self.emoji = emoji
        self.customInstructions = customInstructions
    }

    private enum CodingKeys: String, CodingKey {
        case rewriteEnabled
        case liveTypingEnabled
        case liveFinalizationMode
        case baseTone
        case warmth
        case enthusiasm
        case headersAndLists
        case emoji
        case customInstructions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rewriteEnabled = try container.decode(Bool.self, forKey: .rewriteEnabled)
        liveTypingEnabled = try container.decode(Bool.self, forKey: .liveTypingEnabled)
        liveFinalizationMode = try container.decodeIfPresent(
            DictationLiveFinalizationMode.self,
            forKey: .liveFinalizationMode
        ) ?? .appendOnly
        baseTone = try container.decode(DictationBaseTone.self, forKey: .baseTone)
        warmth = try container.decode(DictationStyleLevel.self, forKey: .warmth)
        enthusiasm = try container.decode(DictationStyleLevel.self, forKey: .enthusiasm)
        headersAndLists = try container.decode(DictationStyleLevel.self, forKey: .headersAndLists)
        emoji = try container.decode(DictationStyleLevel.self, forKey: .emoji)
        customInstructions = try container.decode(String.self, forKey: .customInstructions)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rewriteEnabled, forKey: .rewriteEnabled)
        try container.encode(liveTypingEnabled, forKey: .liveTypingEnabled)
        try container.encode(liveFinalizationMode, forKey: .liveFinalizationMode)
        try container.encode(baseTone, forKey: .baseTone)
        try container.encode(warmth, forKey: .warmth)
        try container.encode(enthusiasm, forKey: .enthusiasm)
        try container.encode(headersAndLists, forKey: .headersAndLists)
        try container.encode(emoji, forKey: .emoji)
        try container.encode(customInstructions, forKey: .customInstructions)
    }

    public static let `default` = DictationRewritePreferences(
        rewriteEnabled: true,
        liveTypingEnabled: false,
        liveFinalizationMode: .appendOnly,
        baseTone: .default,
        warmth: .default,
        enthusiasm: .default,
        headersAndLists: .default,
        emoji: .less,
        customInstructions: ""
    )
}

public struct FeatureFlags: Codable, Equatable, Sendable {
    public let enableGlobalHotkeys: Bool
    public let enableDictation: Bool
    public let enableReadAloud: Bool

    public init(enableGlobalHotkeys: Bool, enableDictation: Bool, enableReadAloud: Bool) {
        self.enableGlobalHotkeys = enableGlobalHotkeys
        self.enableDictation = enableDictation
        self.enableReadAloud = enableReadAloud
    }

    public static let allEnabled = FeatureFlags(
        enableGlobalHotkeys: true,
        enableDictation: true,
        enableReadAloud: true
    )
}

public enum PermissionState: String, Sendable {
    case granted
    case denied
    case notDetermined
}

public struct PermissionStatus: Sendable {
    public let microphone: PermissionState
    public let accessibility: PermissionState
    public let inputMonitoring: PermissionState

    public init(microphone: PermissionState, accessibility: PermissionState, inputMonitoring: PermissionState) {
        self.microphone = microphone
        self.accessibility = accessibility
        self.inputMonitoring = inputMonitoring
    }
}

public struct HotkeyHandlers {
    public let dictationStarted: () -> Void
    public let dictationStopped: () -> Void
    public let readSelectedTriggered: () -> Void

    public init(
        dictationStarted: @escaping () -> Void,
        dictationStopped: @escaping () -> Void,
        readSelectedTriggered: @escaping () -> Void
    ) {
        self.dictationStarted = dictationStarted
        self.dictationStopped = dictationStopped
        self.readSelectedTriggered = readSelectedTriggered
    }
}

public enum FloError: LocalizedError, Sendable {
    case missingOAuthConfiguration
    case oauthFailed(String)
    case unauthorized
    case emptyAudio
    case noSelectedText
    case injectionFailed
    case secureInputActive
    case featureDisabled(String)
    case permissionDenied(String)
    case network(String)
    case persistence(String)

    public var errorDescription: String? {
        switch self {
        case .missingOAuthConfiguration:
            return "ChatGPT OAuth configuration is missing."
        case .oauthFailed(let message):
            return "OAuth failed: \(message)"
        case .unauthorized:
            return "You are not authenticated."
        case .emptyAudio:
            return "No audio was captured."
        case .noSelectedText:
            return "No selected text."
        case .injectionFailed:
            return "Failed to inject transcript into the focused app."
        case .secureInputActive:
            return "Injection blocked while secure input is active."
        case .featureDisabled(let feature):
            return "\(feature) is disabled by configuration."
        case .permissionDenied(let permission):
            return "Permission denied: \(permission)."
        case .network(let message):
            return "Network error: \(message)"
        case .persistence(let message):
            return "Persistence error: \(message)"
        }
    }
}
