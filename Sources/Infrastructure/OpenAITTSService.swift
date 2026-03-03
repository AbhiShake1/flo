import AppCore
import AVFoundation
import Foundation

@MainActor
public final class OpenAITTSService: NSObject, TTSService, @preconcurrency AVAudioPlayerDelegate {
    public enum PlaybackMode {
        case normal
        case skipPlayback
    }

    private let configuration: FloConfiguration
    private let urlSession: URLSession
    private let playbackMode: PlaybackMode
    private var audioPlayer: AVAudioPlayer?
    private var completionContinuation: CheckedContinuation<Void, Error>?
    private var cancelRequested = false

    public init(
        configuration: FloConfiguration,
        urlSession: URLSession = .shared,
        playbackMode: PlaybackMode = .normal
    ) {
        self.configuration = configuration
        self.urlSession = urlSession
        self.playbackMode = playbackMode
    }

    public func synthesizeAndPlay(text: String, authToken: String, voice: String, speed: Double) async throws {
        guard configuration.isAllowedHost(configuration.ttsURL) else {
            throw FloError.network("Blocked host for \(configuration.provider.displayName) TTS endpoint.")
        }

        cancelRequested = false
        let chunks = chunk(text: text, maxLength: max(100, configuration.maxTTSCharactersPerChunk))
        for chunk in chunks {
            if cancelRequested {
                throw CancellationError()
            }

            var request = URLRequest(url: configuration.ttsURL)
            request.httpMethod = "POST"
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let payload: [String: Any] = [
                "model": configuration.ttsModel,
                "voice": voice,
                "speed": min(4.0, max(0.25, speed)),
                "input": chunk,
                "format": "mp3"
            ]

            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ProviderRequestError.invalidResponse(
                    provider: configuration.provider,
                    operation: "tts",
                    message: "Expected HTTP response."
                )
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw ProviderRequestError.http(
                    provider: configuration.provider,
                    operation: "tts",
                    statusCode: httpResponse.statusCode,
                    message: String(data: data, encoding: .utf8) ?? "TTS request failed"
                )
            }

            if case .normal = playbackMode {
                try await playAudio(data: data)
            }
        }
    }

    public func stopPlayback() {
        cancelRequested = true
        audioPlayer?.stop()
        audioPlayer = nil
        let continuation = completionContinuation
        completionContinuation = nil
        continuation?.resume(throwing: CancellationError())
    }

    private func playAudio(data: Data) async throws {
        try await withCheckedThrowingContinuation { continuation in
            do {
                let player = try AVAudioPlayer(data: data)
                player.delegate = self
                player.prepareToPlay()
                audioPlayer = player
                completionContinuation = continuation
                if !player.play() {
                    completionContinuation = nil
                    throw FloError.network("Unable to play synthesized audio")
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let continuation = completionContinuation
        completionContinuation = nil
        audioPlayer = nil
        if flag {
            continuation?.resume()
        } else {
            continuation?.resume(throwing: FloError.network("Playback failed"))
        }
    }

    private func chunk(text: String, maxLength: Int) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxLength else {
            return [trimmed]
        }

        var chunks: [String] = []
        var cursor = trimmed.startIndex

        while cursor < trimmed.endIndex {
            let candidateEnd = trimmed.index(cursor, offsetBy: maxLength, limitedBy: trimmed.endIndex) ?? trimmed.endIndex
            if candidateEnd == trimmed.endIndex {
                chunks.append(String(trimmed[cursor..<candidateEnd]))
                break
            }

            let segment = trimmed[cursor..<candidateEnd]
            if let splitIndex = segment.lastIndex(where: { $0 == "." || $0 == "!" || $0 == "?" || $0 == "\n" || $0 == " " }) {
                let absoluteSplit = splitIndex
                let chunk = String(trimmed[cursor..<absoluteSplit]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !chunk.isEmpty {
                    chunks.append(chunk)
                }
                cursor = trimmed.index(after: absoluteSplit)
            } else {
                chunks.append(String(segment).trimmingCharacters(in: .whitespacesAndNewlines))
                cursor = candidateEnd
            }
        }

        return chunks.filter { !$0.isEmpty }
    }
}
