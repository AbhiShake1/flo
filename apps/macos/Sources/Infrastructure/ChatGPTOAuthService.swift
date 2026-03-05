import AppCore
import CryptoKit
import Foundation
import AppKit
import Network

@MainActor
public final class ChatGPTOAuthService: AuthService {
    private enum Keys {
        static let keychainService = "com.flo.auth"
        static let sessionKey = "oauth_session"
    }

    private static let callbackWaitTimeoutSeconds: TimeInterval = 12

    private struct OAuthTokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String
        let tokenType: String?
        let expiresIn: Int

        private enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case tokenType = "token_type"
            case expiresIn = "expires_in"
        }
    }

    private let configuration: OAuthConfiguration?
    private let urlSession: URLSession

    public init(configuration: OAuthConfiguration?, urlSession: URLSession = .shared) {
        self.configuration = configuration
        self.urlSession = urlSession
    }

    public func restoreSession() async -> UserSession? {
        do {
            guard let data = try KeychainStore.shared.get(key: Keys.sessionKey, service: Keys.keychainService) else {
                return nil
            }
            let session = try JSONDecoder().decode(UserSession.self, from: data)
            if session.isExpired, session.refreshToken != nil {
                let refreshed = try await refreshSession(session)
                return refreshed
            }
            return session
        } catch {
            return nil
        }
    }

    public func startOAuth() async throws -> UserSession {
        guard let configuration else {
            throw FloError.missingOAuthConfiguration
        }
        guard isAllowed(configuration.authorizeURL, in: configuration),
              isAllowed(configuration.tokenURL, in: configuration)
        else {
            throw FloError.oauthFailed("OAuth endpoint blocked by host allowlist")
        }

        let state = Self.randomHex(byteCount: 16)
        let verifier = Self.randomBase64URL(byteCount: 32)
        let challenge = Self.sha256Base64URL(verifier)

        guard let authURL = buildAuthorizeURL(
            configuration: configuration,
            state: state,
            challenge: challenge
        ) else {
            throw FloError.oauthFailed("Unable to build authorization URL")
        }

        var callbackServer = LocalOAuthCallbackServer(redirectURI: configuration.redirectURI, expectedState: state)
        if let server = callbackServer {
            do {
                try await server.start()
            } catch {
                NSLog("Flo OAuth callback server failed to start: %@", String(describing: error))
                callbackServer = nil
            }
        }

        defer {
            callbackServer?.stop()
        }

        guard NSWorkspace.shared.open(authURL) else {
            throw FloError.oauthFailed("Failed to open browser for OAuth login")
        }

        let callbackInput: String
        if let callbackServer {
            if let callbackURLString = await callbackServer.waitForCallback(timeout: Self.callbackWaitTimeoutSeconds) {
                callbackInput = callbackURLString
            } else {
                callbackInput = try promptForManualOAuthInput()
            }
        } else {
            callbackInput = try promptForManualOAuthInput()
        }

        let parsedInput = Self.parseAuthorizationInput(callbackInput)
        if let parsedState = parsedInput.state, parsedState != state {
            throw FloError.oauthFailed("State mismatch")
        }

        guard let code = parsedInput.code, !code.isEmpty else {
            throw FloError.oauthFailed("Authorization code missing")
        }

        let session = try await exchangeCodeForSession(code: code, verifier: verifier, configuration: configuration)
        try persistSession(session)
        return session
    }

    public func refreshSession(_ session: UserSession) async throws -> UserSession {
        guard let configuration, let refreshToken = session.refreshToken else {
            throw FloError.unauthorized
        }
        guard isAllowed(configuration.tokenURL, in: configuration) else {
            throw FloError.oauthFailed("OAuth token endpoint blocked by host allowlist")
        }

        var request = URLRequest(url: configuration.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var formValues = [
            "grant_type": "refresh_token",
            "client_id": configuration.clientID,
            "refresh_token": refreshToken
        ]
        if let clientSecret = configuration.clientSecret {
            formValues["client_secret"] = clientSecret
        }

        request.httpBody = Self.formEncoded(formValues).data(using: .utf8)

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw FloError.oauthFailed(String(data: data, encoding: .utf8) ?? "Refresh failed")
        }

        let tokenResponse = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
        let refreshed = UserSession(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken,
            tokenType: tokenResponse.tokenType ?? session.tokenType,
            expiresAt: Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn)),
            accountID: Self.extractAccountID(from: tokenResponse.accessToken)
        )

        try persistSession(refreshed)
        return refreshed
    }

    public func logout() async {
        do {
            try KeychainStore.shared.delete(key: Keys.sessionKey, service: Keys.keychainService)
        } catch {
            // Best-effort cleanup.
        }
    }

    private func exchangeCodeForSession(
        code: String,
        verifier: String,
        configuration: OAuthConfiguration
    ) async throws -> UserSession {
        guard isAllowed(configuration.tokenURL, in: configuration) else {
            throw FloError.oauthFailed("OAuth token endpoint blocked by host allowlist")
        }

        var request = URLRequest(url: configuration.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var formValues = [
            "grant_type": "authorization_code",
            "client_id": configuration.clientID,
            "code": code,
            "redirect_uri": configuration.redirectURI,
            "code_verifier": verifier
        ]
        if let clientSecret = configuration.clientSecret {
            formValues["client_secret"] = clientSecret
        }

        request.httpBody = Self.formEncoded(formValues).data(using: .utf8)

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw FloError.oauthFailed(String(data: data, encoding: .utf8) ?? "Token exchange failed")
        }

        let tokenResponse = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
        return UserSession(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken,
            tokenType: tokenResponse.tokenType ?? "Bearer",
            expiresAt: Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn)),
            accountID: Self.extractAccountID(from: tokenResponse.accessToken)
        )
    }

    private func persistSession(_ session: UserSession) throws {
        let data = try JSONEncoder().encode(session)
        try KeychainStore.shared.set(data, for: Keys.sessionKey, service: Keys.keychainService)
    }

    private func buildAuthorizeURL(
        configuration: OAuthConfiguration,
        state: String,
        challenge: String
    ) -> URL? {
        guard var components = URLComponents(url: configuration.authorizeURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
            URLQueryItem(name: "scope", value: configuration.scopes),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "id_token_add_organizations", value: "true"),
            URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
            URLQueryItem(name: "originator", value: configuration.originator)
        ]

        return components.url
    }

    private func promptForManualOAuthInput() throws -> String {
        let alert = NSAlert()
        alert.messageText = "Complete ChatGPT Login"
        alert.informativeText = "If browser says localhost cannot be reached, copy and paste the full redirect URL here (or `code#state`)."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")

        let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 24))
        inputField.placeholderString = "http://localhost:1455/auth/callback?code=..."
        alert.accessoryView = inputField

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            throw FloError.oauthFailed("OAuth login canceled")
        }

        let value = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            throw FloError.oauthFailed("Authorization input is required")
        }
        return value
    }

    private static func parseAuthorizationInput(_ input: String) -> (code: String?, state: String?) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return (nil, nil)
        }

        if let callbackURL = URL(string: trimmed),
           let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
        {
            let code = components.queryItems?.first(where: { $0.name == "code" })?.value
            let state = components.queryItems?.first(where: { $0.name == "state" })?.value
            if code != nil || state != nil {
                return (code, state)
            }
        }

        if trimmed.contains("#") {
            let parts = trimmed.split(separator: "#", maxSplits: 1).map(String.init)
            let code = parts.first
            let state = parts.count > 1 ? parts[1] : nil
            return (code, state)
        }

        if trimmed.contains("code="),
           let components = URLComponents(string: "http://localhost?\(trimmed)")
        {
            let code = components.queryItems?.first(where: { $0.name == "code" })?.value
            let state = components.queryItems?.first(where: { $0.name == "state" })?.value
            if code != nil || state != nil {
                return (code, state)
            }
        }

        return (trimmed, nil)
    }

    private static func formEncoded(_ values: [String: String]) -> String {
        values
            .map { key, value in
                "\(formEncodeComponent(key))=\(formEncodeComponent(value))"
            }
            .joined(separator: "&")
    }

    private static func formEncodeComponent(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return (value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)
            .replacingOccurrences(of: "%20", with: "+")
    }

    private static func randomBase64URL(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        if status != errSecSuccess {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func randomHex(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        if status != errSecSuccess {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256Base64URL(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func extractAccountID(from accessToken: String) -> String? {
        let parts = accessToken.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let payloadData = base64URLDecoded(String(parts[1])),
              let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let authClaim = payload["https://api.openai.com/auth"] as? [String: Any],
              let accountID = authClaim["chatgpt_account_id"] as? String,
              !accountID.isEmpty
        else {
            return nil
        }
        return accountID
    }

    private static func base64URLDecoded(_ raw: String) -> Data? {
        var base64 = raw
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }

    private func isAllowed(_ url: URL, in configuration: OAuthConfiguration) -> Bool {
        guard let host = url.host?.lowercased() else {
            return false
        }
        return configuration.allowedHosts.map { $0.lowercased() }.contains(host)
    }
}

private final class LocalOAuthCallbackServer: @unchecked Sendable {
    private static let successHTML = """
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1" />
      <title>Authentication successful</title>
    </head>
    <body>
      <p>Authentication successful. Return to Flo to continue.</p>
    </body>
    </html>
    """

    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.flo.oauth-callback")
    private let expectedPath: String
    private let expectedState: String
    private let callbackHost: String
    private let callbackPort: Int
    private let callbackScheme: String

    private var startContinuation: CheckedContinuation<Void, Error>?
    private var callbackContinuation: CheckedContinuation<String?, Never>?
    private var callbackURLString: String?
    private var didComplete = false

    init?(redirectURI: String, expectedState: String) {
        guard let redirectURL = URL(string: redirectURI),
              let scheme = redirectURL.scheme?.lowercased(),
              scheme == "http",
              let host = redirectURL.host?.lowercased(),
              host == "127.0.0.1" || host == "localhost"
        else {
            return nil
        }

        let path = redirectURL.path.isEmpty ? "/auth/callback" : redirectURL.path
        let port = redirectURL.port ?? 1455
        guard let endpointPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            return nil
        }

        do {
            // Bind by port to support localhost resolving via either IPv4 (127.0.0.1)
            // or IPv6 (::1), which can differ by browser/system configuration.
            listener = try NWListener(using: .tcp, on: endpointPort)
        } catch {
            return nil
        }

        expectedPath = path
        self.expectedState = expectedState
        callbackHost = host
        callbackPort = port
        callbackScheme = scheme
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.startContinuation = continuation
                self.listener.stateUpdateHandler = { [weak self] state in
                    self?.handleListenerState(state)
                }
                self.listener.newConnectionHandler = { [weak self] connection in
                    self?.handleConnection(connection)
                }
                self.listener.start(queue: self.queue)
            }
        }
    }

    func stop() {
        queue.async {
            self.listener.cancel()
            self.finish(with: nil)
        }
    }

    func waitForCallback(timeout: TimeInterval) async -> String? {
        await withCheckedContinuation { continuation in
            queue.async {
                if let callbackURLString = self.callbackURLString {
                    continuation.resume(returning: callbackURLString)
                    return
                }

                self.callbackContinuation = continuation
                self.queue.asyncAfter(deadline: .now() + timeout) {
                    guard let callbackContinuation = self.callbackContinuation else {
                        return
                    }
                    self.callbackContinuation = nil
                    callbackContinuation.resume(returning: nil)
                }
            }
        }
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            if let startContinuation {
                self.startContinuation = nil
                startContinuation.resume()
            }
        case .failed(let error):
            if let startContinuation {
                self.startContinuation = nil
                startContinuation.resume(throwing: error)
            }
            finish(with: nil)
            listener.cancel()
        case .cancelled:
            if let startContinuation {
                self.startContinuation = nil
                startContinuation.resume(throwing: FloError.oauthFailed("OAuth callback listener canceled"))
            }
            finish(with: nil)
        default:
            break
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, _, _ in
            guard let self else {
                connection.cancel()
                return
            }

            guard let data,
                  let request = String(data: data, encoding: .utf8),
                  let requestLine = request.split(separator: "\r\n").first
            else {
                self.respond(connection: connection, statusCode: 400, body: "Invalid request")
                connection.cancel()
                return
            }

            let pieces = requestLine.split(separator: " ")
            guard pieces.count >= 2, pieces[0] == "GET" else {
                self.respond(connection: connection, statusCode: 405, body: "Method not allowed")
                connection.cancel()
                return
            }

            let target = String(pieces[1])
            guard let targetComponents = URLComponents(string: target) else {
                self.respond(connection: connection, statusCode: 400, body: "Invalid callback URL")
                connection.cancel()
                return
            }

            guard targetComponents.path == self.expectedPath else {
                self.respond(connection: connection, statusCode: 404, body: "Not found")
                connection.cancel()
                return
            }

            guard targetComponents.queryItems?.first(where: { $0.name == "state" })?.value == self.expectedState else {
                self.respond(connection: connection, statusCode: 400, body: "State mismatch")
                connection.cancel()
                return
            }

            guard targetComponents.queryItems?.first(where: { $0.name == "code" })?.value != nil else {
                self.respond(connection: connection, statusCode: 400, body: "Missing authorization code")
                connection.cancel()
                return
            }

            var callbackComponents = URLComponents()
            callbackComponents.scheme = self.callbackScheme
            callbackComponents.host = self.callbackHost
            callbackComponents.port = self.callbackPort
            callbackComponents.path = targetComponents.path
            callbackComponents.percentEncodedQuery = targetComponents.percentEncodedQuery

            self.respond(
                connection: connection,
                statusCode: 200,
                body: Self.successHTML,
                contentType: "text/html; charset=utf-8"
            )
            connection.cancel()

            if let callbackURLString = callbackComponents.string {
                self.finish(with: callbackURLString)
            } else {
                self.finish(with: nil)
            }
        }
    }

    private func respond(
        connection: NWConnection,
        statusCode: Int,
        body: String,
        contentType: String = "text/plain; charset=utf-8"
    ) {
        let response = """
        HTTP/1.1 \(statusCode) \(statusText(for: statusCode))
        Content-Type: \(contentType)
        Content-Length: \(body.utf8.count)
        Connection: close

        \(body)
        """
        let data = Data(response.utf8)
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    private func finish(with callbackURLString: String?) {
        guard !didComplete else {
            return
        }
        didComplete = true
        self.callbackURLString = callbackURLString
        if let callbackContinuation {
            self.callbackContinuation = nil
            callbackContinuation.resume(returning: callbackURLString)
        }
    }

    private func statusText(for statusCode: Int) -> String {
        switch statusCode {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        default: return "Error"
        }
    }
}
