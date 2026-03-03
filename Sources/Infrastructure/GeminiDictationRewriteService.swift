import AppCore
import Foundation

public final class GeminiDictationRewriteService: DictationRewriteService, @unchecked Sendable {
    private struct ResponsePayload: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable {
                struct Part: Decodable {
                    let text: String?
                }

                let parts: [Part]?
            }

            let content: Content?
        }

        let candidates: [Candidate]?
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
            throw FloError.network("Blocked host for rewrite endpoint.")
        }

        var request = URLRequest(url: configuration.rewriteURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(authToken, forHTTPHeaderField: "x-goog-api-key")

        let instruction = styleInstruction(for: preferences)
        let payload: [String: Any] = [
            "model": configuration.rewriteModel,
            "contents": [[
                "parts": [
                    ["text": """
                    Rewrite the dictation into clean, ready-to-paste text.
                    Preserve factual meaning exactly.
                    Return only the rewritten text with no explanation.

                    Style guide:
                    \(instruction)

                    Raw transcript:
                    \(raw)
                    """]
                ]
            ]],
            "generationConfig": [
                "temperature": 0.2
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FloError.network("Invalid rewrite response")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw FloError.network(String(data: data, encoding: .utf8) ?? "Rewrite request failed")
        }

        let decoded = try JSONDecoder().decode(ResponsePayload.self, from: data)
        let rewritten = decoded.candidates?
            .compactMap { $0.content?.parts?.compactMap(\.text).joined(separator: "\n") }
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
