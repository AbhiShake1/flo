import AppCore
import Foundation

public final class OpenAIDictationRewriteService: DictationRewriteService, @unchecked Sendable {
    private struct ResponsePayload: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                struct ContentPart: Decodable {
                    let text: String?
                }

                let content: String

                private enum CodingKeys: String, CodingKey {
                    case content
                }

                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    if let value = try? container.decode(String.self, forKey: .content) {
                        content = value
                        return
                    }
                    if let parts = try? container.decode([ContentPart].self, forKey: .content) {
                        content = parts.compactMap(\.text).joined(separator: "\n")
                        return
                    }
                    content = ""
                }
            }

            let message: Message?
        }

        let choices: [Choice]?
    }

    private let configuration: FloConfiguration
    private let urlSession: URLSession

    public init(configuration: FloConfiguration, urlSession: URLSession = .shared) {
        self.configuration = configuration
        self.urlSession = urlSession
    }

    public func rewrite(
        transcript: String,
        authToken: String,
        preferences: DictationRewritePreferences
    ) async throws -> String {
        let raw = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard preferences.rewriteEnabled else {
            return raw
        }
        guard !raw.isEmpty else {
            return raw
        }
        guard configuration.isAllowedHost(configuration.rewriteURL) else {
            throw FloError.network("Blocked host for \(configuration.provider.displayName) rewrite endpoint.")
        }

        var request = URLRequest(url: configuration.rewriteURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let instruction = styleInstruction(for: preferences)
        let payload: [String: Any] = [
            "model": configuration.rewriteModel,
            "temperature": 0.2,
            "messages": [
                [
                    "role": "system",
                    "content": "Rewrite dictation into clean, ready-to-paste text. Preserve factual meaning exactly and return only rewritten text."
                ],
                [
                    "role": "user",
                    "content": """
                    Style guide:
                    \(instruction)

                    Raw transcript:
                    \(raw)
                    """
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderRequestError.invalidResponse(
                provider: configuration.provider,
                operation: "rewrite",
                message: "Expected HTTP response."
            )
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ProviderRequestError.http(
                provider: configuration.provider,
                operation: "rewrite",
                statusCode: httpResponse.statusCode,
                message: String(data: data, encoding: .utf8) ?? "Rewrite request failed"
            )
        }

        let decoded = try JSONDecoder().decode(ResponsePayload.self, from: data)
        let rewritten = decoded.choices?
            .compactMap { $0.message?.content }
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return rewritten.isEmpty ? raw : rewritten
    }

    private func styleInstruction(for preferences: DictationRewritePreferences) -> String {
        var rules: [String] = []
        rules.append("Base tone: \(preferences.baseTone.displayName).")
        rules.append(levelInstruction(label: "Warmth", level: preferences.warmth, more: "Use warmer and more personable wording.", less: "Use professional and factual wording."))
        rules.append(levelInstruction(label: "Enthusiasm", level: preferences.enthusiasm, more: "Use energetic, vivid language.", less: "Use calm and neutral language."))
        rules.append(levelInstruction(label: "Headers and lists", level: preferences.headersAndLists, more: "Use clear headings and bullet lists when useful.", less: "Prefer short paragraphs instead of lists."))
        rules.append(levelInstruction(label: "Emoji", level: preferences.emoji, more: "Use a few suitable emoji.", less: "Avoid emoji."))

        let custom = preferences.customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            rules.append("Custom instructions: \(custom)")
        }

        rules.append("Fix punctuation, grammar, and sentence boundaries.")
        return rules.joined(separator: "\n")
    }

    private func levelInstruction(label: String, level: DictationStyleLevel, more: String, less: String) -> String {
        switch level {
        case .more:
            return "\(label): \(more)"
        case .less:
            return "\(label): \(less)"
        case .default:
            return "\(label): keep balanced defaults."
        }
    }
}
