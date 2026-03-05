import AppCore
import Foundation

public final class GeminiTranscriptionService: TranscriptionService, @unchecked Sendable {
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
    private static let noSpeechToken = "__NO_SPEECH__"

    public init(configuration: FloConfiguration, urlSession: URLSession = .shared) {
        self.configuration = configuration
        self.urlSession = urlSession
    }

    public func transcribe(audioFileURL: URL, authToken: String) async throws -> TranscriptResult {
        guard configuration.isAllowedHost(configuration.transcriptionURL) else {
            throw FloError.network("Blocked host for \(configuration.provider.displayName) transcription endpoint.")
        }

        let mimeType = audioFileURL.pathExtension.lowercased() == "wav" ? "audio/wav" : "audio/mp4"
        let audioData = try Data(contentsOf: audioFileURL)
        let startedAt = Date()

        var request = URLRequest(url: configuration.transcriptionURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(authToken, forHTTPHeaderField: "x-goog-api-key")

        let payload: [String: Any] = [
            "model": configuration.transcriptionModel,
            "contents": [[
                "parts": [
                    ["text": """
                    You are a speech-to-text engine.
                    Task: transcribe spoken words from the provided audio exactly.
                    Return only transcript text.
                    Do not add commentary, explanations, or metadata.
                    If no intelligible speech is present, return exactly \(Self.noSpeechToken)
                    """],
                    [
                        "inline_data": [
                            "mime_type": mimeType,
                            "data": audioData.base64EncodedString()
                        ]
                    ]
                ]
            ]],
            "generationConfig": [
                "temperature": 0
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderRequestError.invalidResponse(
                provider: configuration.provider,
                operation: "transcription",
                message: "Expected HTTP response."
            )
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ProviderRequestError.http(
                provider: configuration.provider,
                operation: "transcription",
                statusCode: httpResponse.statusCode,
                message: String(data: data, encoding: .utf8) ?? "\(configuration.provider.displayName) transcription request failed"
            )
        }

        let decoded = try JSONDecoder().decode(ResponsePayload.self, from: data)
        let transcript = decoded.candidates?
            .compactMap { $0.content?.parts?.compactMap(\.text).joined(separator: "\n") }
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let normalized = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw FloError.network("Gemini transcription returned empty text.")
        }
        if normalized == Self.noSpeechToken {
            throw FloError.emptyAudio
        }
        if Self.looksLikeNonTranscriptResponse(normalized) {
            throw FloError.network("Gemini returned a non-transcription response.")
        }

        let elapsed = Int(Date().timeIntervalSince(startedAt) * 1000)
        let requestID = httpResponse.value(forHTTPHeaderField: "x-request-id")
            ?? httpResponse.value(forHTTPHeaderField: "x-goog-request-id")
        return TranscriptResult(
            text: normalized,
            requestID: requestID,
            latencyMs: elapsed,
            confidence: nil
        )
    }

    private static func looksLikeNonTranscriptResponse(_ text: String) -> Bool {
        let normalized = text.lowercased()
        let rejectionPhrases = [
            "please provide the audio file",
            "auditory input",
            "input required",
            "current operational status",
            "i need the audio",
            "cannot transcribe without audio"
        ]
        return rejectionPhrases.contains { normalized.contains($0) }
    }
}
