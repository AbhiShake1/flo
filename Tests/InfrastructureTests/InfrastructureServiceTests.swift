import AppCore
import Foundation
import Infrastructure
import Testing

@Suite("Infrastructure Service Tests", .serialized)
struct InfrastructureServiceTests {
    @Test
    func transcriptionRetriesAfterNetworkFailure() async throws {
        URLProtocolStub.reset()

        let fileURL = try temporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let session = makeSession()
        let counter = LockedCounter()

        URLProtocolStub.handler = { request in
            let attempt = counter.next()
            if attempt == 1 {
                throw URLError(.notConnectedToInternet)
            }

            let body = "{\"text\":\"hello world\",\"confidence\":0.91}".data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["x-request-id": "req_123"]
            )!
            return (response, body)
        }

        let service = OpenAITranscriptionService(configuration: makeConfiguration(), urlSession: session)
        let result = try await service.transcribe(audioFileURL: fileURL, authToken: "token")

        #expect(result.text == "hello world")
        #expect(result.requestID == "req_123")
        #expect(result.confidence == 0.91)
        #expect(counter.current == 2)
    }

    @Test
    func transcriptionRetriesOnThrottlingStatus() async throws {
        URLProtocolStub.reset()

        let fileURL = try temporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let session = makeSession()
        let counter = LockedCounter()

        URLProtocolStub.handler = { request in
            let attempt = counter.next()
            if attempt == 1 {
                let response = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!
                return (response, Data("rate limited".utf8))
            }

            let body = "{\"text\":\"retry ok\"}".data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }

        let service = OpenAITranscriptionService(configuration: makeConfiguration(), urlSession: session)
        let result = try await service.transcribe(audioFileURL: fileURL, authToken: "token")

        #expect(result.text == "retry ok")
        #expect(counter.current == 2)
    }

    @Test
    func transcriptionRejectsDisallowedHost() async throws {
        URLProtocolStub.reset()

        let fileURL = try temporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let service = OpenAITranscriptionService(
            configuration: makeConfiguration(hostAllowlist: ["other-host.example"]),
            urlSession: makeSession()
        )

        do {
            _ = try await service.transcribe(audioFileURL: fileURL, authToken: "token")
            Issue.record("Expected host allowlist rejection")
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            #expect(message.contains("Blocked host"))
        }
    }

    @Test
    func transcriptionDerivesConfidenceFromSegmentLogProb() async throws {
        URLProtocolStub.reset()

        let fileURL = try temporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        URLProtocolStub.handler = { request in
            let body = "{\"text\":\"derived\",\"segments\":[{\"avg_logprob\":-0.3},{\"avg_logprob\":-0.5}]}".data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }

        let service = OpenAITranscriptionService(configuration: makeConfiguration(), urlSession: makeSession())
        let result = try await service.transcribe(audioFileURL: fileURL, authToken: "token")

        #expect(result.text == "derived")
        #expect(result.confidence != nil)
    }

    @Test
    func geminiTranscriptionRejectsNonTranscriptResponse() async throws {
        URLProtocolStub.reset()

        let fileURL = try temporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        URLProtocolStub.handler = { request in
            let body = """
            {
              "candidates": [
                {
                  "content": {
                    "parts": [
                      { "text": "Current Operational Status: Input Required! Please provide the audio file." }
                    ]
                  }
                }
              ]
            }
            """.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }

        let service = GeminiTranscriptionService(configuration: makeGeminiConfiguration(), urlSession: makeSession())
        do {
            _ = try await service.transcribe(audioFileURL: fileURL, authToken: "token")
            Issue.record("Expected Gemini non-transcript response rejection")
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            #expect(message.contains("non-transcription response"))
        }
    }

    @Test
    func shortcutStoreRoundTripsBindings() throws {
        let suiteName = "flo.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create UserDefaults suite")
            return
        }

        defaults.removePersistentDomain(forName: suiteName)

        let store = UserDefaultsShortcutStore(defaults: defaults)
        let bindings = [
            ShortcutBinding(action: .dictationHold, combo: KeyCombo(keyCode: 49, modifiers: [.control, .option], keyDisplay: "Space")),
            ShortcutBinding(action: .readSelectedText, combo: KeyCombo(keyCode: 15, modifiers: [.option], keyDisplay: "R"))
        ]

        store.saveBindings(bindings)
        let loaded = store.loadBindings()

        #expect(loaded.count == 2)
        #expect(loaded.first(where: { $0.action == .dictationHold })?.combo == bindings[0].combo)
        #expect(loaded.first(where: { $0.action == .readSelectedText })?.combo == bindings[1].combo)
    }

    @Test
    func voicePreferencesStoreRoundTripsValues() {
        let suiteName = "flo.tests.voice.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let store = UserDefaultsVoicePreferencesStore(defaults: defaults)
        store.save(VoicePreferences(voice: "nova", speed: 1.4))
        let loaded = store.load()

        #expect(loaded.voice == "nova")
        #expect(loaded.speed == 1.4)
    }

    @Test
    func dictationRewritePreferencesStoreRoundTripsValues() {
        let suiteName = "flo.tests.rewrite.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let store = UserDefaultsDictationRewritePreferencesStore(defaults: defaults)
        let expected = DictationRewritePreferences(
            rewriteEnabled: true,
            liveTypingEnabled: true,
            liveFinalizationMode: .replaceWithFinal,
            baseTone: .professional,
            warmth: .less,
            enthusiasm: .more,
            headersAndLists: .more,
            emoji: .less,
            customInstructions: "Be pragmatic."
        )
        store.save(expected)
        let loaded = store.load()

        #expect(loaded == expected)
    }

    @Test
    func onboardingStoreRoundTripsState() {
        let suiteName = "flo.tests.onboarding.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let store = UserDefaultsOnboardingStateStore(defaults: defaults)
        #expect(store.hasCompletedHotkeyConfirmation() == false)
        store.setHotkeyConfirmationCompleted(true)
        #expect(store.hasCompletedHotkeyConfirmation() == true)
    }

    @Test
    func secureHistoryStoreAppendsLoadsAndClears() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("flo-history-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let store = SecureSessionHistoryStore(baseDirectoryURL: baseDirectory)
        let entry = HistoryEntry(
            kind: .dictation,
            inputText: "hello",
            outputText: "hello",
            requestID: "req_1",
            latencyMs: 123,
            success: true,
            errorMessage: nil
        )

        try store.append(entry)
        let loaded = try store.load()
        #expect(loaded.count == 1)
        #expect(loaded.first?.requestID == "req_1")
        #expect(loaded.first?.latencyMs == 123)

        try store.clear()
        let cleared = try store.load()
        #expect(cleared.isEmpty)
    }

    @Test
    func secureHistoryStoreRecoversFromCorruptedPayload() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("flo-history-corrupt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let appDirectory = baseDirectory.appendingPathComponent("flo", isDirectory: true)
        try FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        let historyPath = appDirectory.appendingPathComponent("history.enc")
        try Data([0x00, 0x01, 0x02, 0x03]).write(to: historyPath, options: .atomic)

        let store = SecureSessionHistoryStore(baseDirectoryURL: baseDirectory)
        let recovered = try store.load()
        #expect(recovered.isEmpty)
        #expect(FileManager.default.fileExists(atPath: historyPath.path) == false)

        let newEntry = HistoryEntry(
            kind: .dictation,
            inputText: "recovered",
            outputText: "recovered",
            requestID: "req_recovered",
            latencyMs: 42,
            success: true,
            errorMessage: nil
        )
        try store.append(newEntry)
        let loadedAfterRecovery = try store.load()
        #expect(loadedAfterRecovery.count == 1)
        #expect(loadedAfterRecovery.first?.requestID == "req_recovered")
    }

    @Test
    func configurationParsesFeatureFlagsFromEnvironment() {
        let env = [
            "FLO_FEATURE_GLOBAL_HOTKEYS": "false",
            "FLO_FEATURE_DICTATION": "true",
            "FLO_FEATURE_READ_ALOUD": "0",
            "FLO_OPENAI_TRANSCRIPTION_URL": "https://api.openai.com/v1/audio/transcriptions",
            "FLO_OPENAI_TTS_URL": "https://api.openai.com/v1/audio/speech"
        ]

        let configuration = FloConfiguration.loadFromEnvironment(env)
        #expect(configuration.featureFlags.enableGlobalHotkeys == false)
        #expect(configuration.featureFlags.enableDictation == true)
        #expect(configuration.featureFlags.enableReadAloud == false)
    }

    @Test
    func configurationIgnoresBlankOAuthAndApiKeyValues() {
        let env = [
            "FLO_OPENAI_API_KEY": "   ",
            "FLO_CHATGPT_AUTH_URL": "https://auth.openai.com/authorize",
            "FLO_CHATGPT_TOKEN_URL": "https://auth.openai.com/oauth/token",
            "FLO_CHATGPT_CLIENT_ID": "   ",
            "FLO_CHATGPT_REDIRECT_URI": "   ",
            "FLO_OPENAI_TRANSCRIPTION_URL": "https://api.openai.com/v1/audio/transcriptions",
            "FLO_OPENAI_TTS_URL": "https://api.openai.com/v1/audio/speech"
        ]

        let configuration = FloConfiguration.loadFromEnvironment(env)
        #expect(configuration.openAIApiKey == nil)
        #expect(configuration.oauth?.clientID == OAuthConfiguration.defaultClientID)
        #expect(configuration.oauth?.redirectURI == OAuthConfiguration.defaultRedirectURI)
    }

    @Test
    func configurationUsesCodexOAuthDefaultsWhenUnset() {
        let env = [
            "FLO_OPENAI_TRANSCRIPTION_URL": "https://api.openai.com/v1/audio/transcriptions",
            "FLO_OPENAI_TTS_URL": "https://api.openai.com/v1/audio/speech"
        ]

        let configuration = FloConfiguration.loadFromEnvironment(env)
        #expect(configuration.oauth?.authorizeURL.absoluteString == OAuthConfiguration.defaultAuthorizeURL.absoluteString)
        #expect(configuration.oauth?.tokenURL.absoluteString == OAuthConfiguration.defaultTokenURL.absoluteString)
        #expect(configuration.oauth?.clientID == OAuthConfiguration.defaultClientID)
        #expect(configuration.oauth?.redirectURI == OAuthConfiguration.defaultRedirectURI)
        #expect(configuration.oauth?.scopes == OAuthConfiguration.defaultScopes)
        #expect(configuration.oauth?.originator == OAuthConfiguration.defaultOriginator)
    }

    @Test
    func configurationAllowsExplicitOAuthDisable() {
        let env = [
            "FLO_CHATGPT_OAUTH_ENABLED": "false",
            "FLO_OPENAI_TRANSCRIPTION_URL": "https://api.openai.com/v1/audio/transcriptions",
            "FLO_OPENAI_TTS_URL": "https://api.openai.com/v1/audio/speech"
        ]

        let configuration = FloConfiguration.loadFromEnvironment(env)
        #expect(configuration.oauth == nil)
    }

    @Test
    func configurationUsesGeminiProviderWhenSelected() {
        let env = [
            "FLO_AI_PROVIDER": "gemini",
            "FLO_GEMINI_API_KEY": "gemini_key_123"
        ]

        let configuration = FloConfiguration.loadFromEnvironment(env)
        #expect(configuration.provider == .gemini)
        #expect(configuration.geminiApiKey == "gemini_key_123")
        #expect(configuration.localCredentialToken == "gemini_key_123")
        #expect(configuration.oauth == nil)
        #expect(configuration.transcriptionURL.host == "generativelanguage.googleapis.com")
        #expect(configuration.ttsURL.host == "generativelanguage.googleapis.com")
    }

    @Test
    func localEnvLoaderFallsBackToBundleResourcesWhenCwdDoesNotContainEnvFiles() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("flo-env-loader-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let cwd = temporaryRoot.appendingPathComponent("cwd", isDirectory: true)
        let resources = temporaryRoot.appendingPathComponent("Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)

        let envContent = """
        FLO_AI_PROVIDER=gemini
        FLO_GEMINI_API_KEY=bundle_key_123
        """
        try envContent.write(to: resources.appendingPathComponent(".env.local"), atomically: true, encoding: .utf8)

        let merged = LocalEnvLoader.mergedEnvironment(
            processEnvironment: [:],
            cwd: cwd,
            bundleResourceURL: resources,
            executableURL: nil
        )

        #expect(merged["FLO_AI_PROVIDER"] == "gemini")
        #expect(merged["FLO_GEMINI_API_KEY"] == "bundle_key_123")
    }

    @Test
    func localEnvLoaderFallsBackToExecutableAncestors() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("flo-env-exe-loader-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let projectRoot = temporaryRoot.appendingPathComponent("project", isDirectory: true)
        let executableDirectory = projectRoot
            .appendingPathComponent(".build/debug", isDirectory: true)
        let unrelatedCwd = temporaryRoot.appendingPathComponent("other-cwd", isDirectory: true)
        try FileManager.default.createDirectory(at: executableDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: unrelatedCwd, withIntermediateDirectories: true)

        let envContent = """
        FLO_AI_PROVIDER=gemini
        FLO_GEMINI_API_KEY=ancestor_key_456
        """
        try envContent.write(
            to: projectRoot.appendingPathComponent(".env.local"),
            atomically: true,
            encoding: .utf8
        )

        let merged = LocalEnvLoader.mergedEnvironment(
            processEnvironment: [:],
            cwd: unrelatedCwd,
            bundleResourceURL: nil,
            executableURL: executableDirectory.appendingPathComponent("FloApp")
        )

        #expect(merged["FLO_AI_PROVIDER"] == "gemini")
        #expect(merged["FLO_GEMINI_API_KEY"] == "ancestor_key_456")
    }

    @Test
    @MainActor
    func oauthRefreshIncludesClientSecretWhenProvided() async throws {
        URLProtocolStub.reset()
        let capturedBodies = LockedDataArray()

        URLProtocolStub.handler = { request in
            if let body = requestBodyData(request) {
                capturedBodies.append(body)
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let payload = "{\"access_token\":\"new_access\",\"refresh_token\":\"new_refresh\",\"token_type\":\"Bearer\",\"expires_in\":3600}"
            return (response, Data(payload.utf8))
        }

        let oauth = OAuthConfiguration(
            authorizeURL: URL(string: "https://auth.openai.com/authorize")!,
            tokenURL: URL(string: "https://auth.openai.com/oauth/token")!,
            clientID: "client_123",
            clientSecret: "secret_123",
            redirectURI: "http://localhost:1455/auth/callback",
            scopes: "openid profile email offline_access",
            originator: "pi"
        )

        let service = ChatGPTOAuthService(configuration: oauth, urlSession: makeSession())
        let currentSession = UserSession(
            accessToken: "old_access",
            refreshToken: "refresh_123",
            tokenType: "Bearer",
            expiresAt: Date().addingTimeInterval(-300)
        )

        _ = try await service.refreshSession(currentSession)

        guard let bodyData = capturedBodies.first, let body = String(data: bodyData, encoding: .utf8) else {
            Issue.record("Expected OAuth refresh request body.")
            return
        }

        #expect(body.contains("client_id=client_123"))
        #expect(body.contains("refresh_token=refresh_123"))
        #expect(body.contains("client_secret=secret_123"))
    }

    @Test
    @MainActor
    func oauthRefreshExtractsAccountIDFromJWTAccessToken() async throws {
        URLProtocolStub.reset()

        URLProtocolStub.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let token = makeCodexAccessToken(accountID: "acc_123")
            let payload = """
            {"access_token":"\(token)","refresh_token":"new_refresh","token_type":"Bearer","expires_in":3600}
            """
            return (response, Data(payload.utf8))
        }

        let oauth = OAuthConfiguration(
            authorizeURL: URL(string: "https://auth.openai.com/authorize")!,
            tokenURL: URL(string: "https://auth.openai.com/oauth/token")!,
            clientID: "client_123",
            clientSecret: nil,
            redirectURI: "http://localhost:1455/auth/callback",
            scopes: "openid profile email offline_access",
            originator: "pi"
        )

        let service = ChatGPTOAuthService(configuration: oauth, urlSession: makeSession())
        let currentSession = UserSession(
            accessToken: "old_access",
            refreshToken: "refresh_123",
            tokenType: "Bearer",
            expiresAt: Date().addingTimeInterval(-300)
        )

        let refreshed = try await service.refreshSession(currentSession)
        #expect(refreshed.accountID == "acc_123")
    }

    @Test
    @MainActor
    func oauthRefreshFailsWhenRequiredFieldsAreMissing() async {
        URLProtocolStub.reset()

        URLProtocolStub.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("{\"access_token\":\"only_access\"}".utf8))
        }

        let oauth = OAuthConfiguration(
            authorizeURL: URL(string: "https://auth.openai.com/authorize")!,
            tokenURL: URL(string: "https://auth.openai.com/oauth/token")!,
            clientID: "client_123",
            clientSecret: nil,
            redirectURI: "http://localhost:1455/auth/callback",
            scopes: "openid profile email offline_access",
            originator: "pi"
        )

        let service = ChatGPTOAuthService(configuration: oauth, urlSession: makeSession())
        let currentSession = UserSession(
            accessToken: "old_access",
            refreshToken: "refresh_123",
            tokenType: "Bearer",
            expiresAt: Date().addingTimeInterval(-300)
        )

        do {
            _ = try await service.refreshSession(currentSession)
            Issue.record("Expected refresh to fail when token payload omits required fields.")
        } catch {
            #expect(String(describing: error).isEmpty == false)
        }
    }

    @Test
    @MainActor
    func ttsBuildsChunkedRequestsWithSelectedVoiceAndSpeed() async throws {
        URLProtocolStub.reset()
        let capturedBodies = LockedDataArray()
        let longText = Array(repeating: "Chunk me please.", count: 20).joined(separator: " ")

        URLProtocolStub.handler = { request in
            if let body = requestBodyData(request) {
                capturedBodies.append(body)
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let configuration = makeConfiguration(maxTTSCharactersPerChunk: 45)
        let service = OpenAITTSService(configuration: configuration, urlSession: makeSession(), playbackMode: .skipPlayback)
        try await service.synthesizeAndPlay(
            text: longText,
            authToken: "token",
            voice: "nova",
            speed: 1.3
        )

        #expect(capturedBodies.count > 1)

        if let first = capturedBodies.first,
           let json = try JSONSerialization.jsonObject(with: first) as? [String: Any]
        {
            #expect((json["voice"] as? String) == "nova")
            #expect((json["speed"] as? Double) == 1.3)
            #expect((json["input"] as? String)?.isEmpty == false)
        } else {
            Issue.record("Expected at least one JSON payload for TTS request body.")
        }
    }
}

private func makeSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [URLProtocolStub.self]
    return URLSession(configuration: configuration)
}

private func makeConfiguration(
    hostAllowlist: Set<String> = ["api.openai.com"],
    maxTTSCharactersPerChunk: Int = 1500
) -> FloConfiguration {
    FloConfiguration(
        transcriptionURL: URL(string: "https://api.openai.com/v1/audio/transcriptions")!,
        ttsURL: URL(string: "https://api.openai.com/v1/audio/speech")!,
        rewriteURL: URL(string: "https://api.openai.com/v1/chat/completions")!,
        openAIApiKey: nil,
        transcriptionModel: "gpt-4o-mini-transcribe",
        ttsModel: "gpt-4o-mini-tts",
        rewriteModel: "gpt-4o-mini",
        ttsVoice: "alloy",
        ttsSpeed: 1.0,
        maxTTSCharactersPerChunk: maxTTSCharactersPerChunk,
        retainAudioDebugArtifacts: false,
        hostAllowlist: hostAllowlist,
        featureFlags: .allEnabled,
        manualUpdateURL: nil,
        oauth: nil
    )
}

private func makeGeminiConfiguration() -> FloConfiguration {
    FloConfiguration(
        provider: .gemini,
        transcriptionURL: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent")!,
        ttsURL: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-tts:generateContent")!,
        rewriteURL: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent")!,
        openAIApiKey: nil,
        geminiApiKey: "gemini_key",
        transcriptionModel: "models/gemini-2.5-flash",
        ttsModel: "models/gemini-2.5-flash-preview-tts",
        rewriteModel: "models/gemini-2.5-flash",
        ttsVoice: "alloy",
        ttsSpeed: 1.0,
        maxTTSCharactersPerChunk: 1500,
        retainAudioDebugArtifacts: false,
        hostAllowlist: ["generativelanguage.googleapis.com"],
        featureFlags: .allEnabled,
        manualUpdateURL: nil,
        oauth: nil
    )
}

private func temporaryAudioFile() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("flo-test-audio-\(UUID().uuidString)")
        .appendingPathExtension("wav")
    try Data([0x00, 0x01, 0x02, 0x03]).write(to: url)
    return url
}

private func requestBodyData(_ request: URLRequest) -> Data? {
    if let body = request.httpBody {
        return body
    }

    guard let stream = request.httpBodyStream else {
        return nil
    }

    stream.open()
    defer { stream.close() }

    var data = Data()
    let bufferSize = 4096
    var buffer = [UInt8](repeating: 0, count: bufferSize)

    while stream.hasBytesAvailable {
        let readCount = stream.read(&buffer, maxLength: bufferSize)
        if readCount < 0 {
            return nil
        }
        if readCount == 0 {
            break
        }
        data.append(buffer, count: readCount)
    }

    return data.isEmpty ? nil : data
}

private func makeCodexAccessToken(accountID: String) -> String {
    let header = ["alg": "none", "typ": "JWT"]
    let payload: [String: Any] = [
        "https://api.openai.com/auth": [
            "chatgpt_account_id": accountID
        ]
    ]
    return "\(base64URLEncodeJSON(header)).\(base64URLEncodeJSON(payload)).signature"
}

private func base64URLEncodeJSON(_ value: Any) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: value) else {
        return ""
    }
    return data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var current: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}

private final class LockedDataArray: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Data] = []

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return values.count
    }

    var first: Data? {
        lock.lock()
        defer { lock.unlock() }
        return values.first
    }

    func append(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        values.append(data)
    }
}

private final class URLProtocolStub: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    static func reset() {
        handler = nil
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
