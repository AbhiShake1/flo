import AppCore
import AVFoundation
import Foundation

@MainActor
public final class GeminiTTSService: NSObject, TTSService, @preconcurrency AVAudioPlayerDelegate {
    private struct ResponsePayload: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable {
                struct Part: Decodable {
                    struct InlineData: Decodable {
                        let data: String?
                    }

                    let inlineData: InlineData?
                    let inline_data: InlineData?

                    private enum CodingKeys: String, CodingKey {
                        case inlineData
                        case inline_data
                    }

                    var base64AudioData: String? {
                        inlineData?.data ?? inline_data?.data
                    }
                }

                let parts: [Part]?
            }

            let content: Content?
        }

        let candidates: [Candidate]?
    }

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
            throw FloError.network("Blocked host for Gemini TTS endpoint.")
        }

        cancelRequested = false
        let chunks = chunk(text: text, maxLength: max(100, configuration.maxTTSCharactersPerChunk))
        for chunk in chunks {
            if cancelRequested {
                throw CancellationError()
            }

            var request = URLRequest(url: configuration.ttsURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(authToken, forHTTPHeaderField: "x-goog-api-key")

            let payload: [String: Any] = [
                "model": configuration.ttsModel,
                "contents": [[
                    "parts": [
                        ["text": chunk]
                    ]
                ]],
                "generationConfig": [
                    "responseModalities": ["AUDIO"],
                    "speechConfig": [
                        "voiceConfig": [
                            "prebuiltVoiceConfig": [
                                "voiceName": voice
                            ]
                        ]
                    ]
                ]
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw FloError.network("Invalid Gemini TTS response")
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw FloError.network(String(data: data, encoding: .utf8) ?? "Gemini TTS request failed")
            }

            let decoded = try JSONDecoder().decode(ResponsePayload.self, from: data)
            let audioPart = decoded.candidates?
                .first?
                .content?
                .parts?
                .first(where: { ($0.base64AudioData ?? "").isEmpty == false })
            guard let base64 = audioPart?.base64AudioData,
                let pcmData = Data(base64Encoded: base64)
            else {
                throw FloError.network("Gemini TTS response is missing audio data.")
            }

            let wavData = Self.wrapPCMAsWav(pcmData)
            if case .normal = playbackMode {
                try await playAudio(data: wavData)
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
                    throw FloError.network("Unable to play Gemini synthesized audio")
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

    private static func wrapPCMAsWav(
        _ pcmData: Data,
        sampleRate: UInt32 = 24_000,
        channels: UInt16 = 1,
        bitsPerSample: UInt16 = 16
    ) -> Data {
        let bytesPerSample = UInt16(bitsPerSample / 8)
        let byteRate = sampleRate * UInt32(channels * bytesPerSample)
        let blockAlign = channels * bytesPerSample
        let dataChunkSize = UInt32(pcmData.count)
        let riffChunkSize = 36 + dataChunkSize

        var wavData = Data()
        wavData.append("RIFF".data(using: .ascii)!)
        wavData.append(Self.le32(riffChunkSize))
        wavData.append("WAVE".data(using: .ascii)!)
        wavData.append("fmt ".data(using: .ascii)!)
        wavData.append(Self.le32(16))
        wavData.append(Self.le16(1))
        wavData.append(Self.le16(channels))
        wavData.append(Self.le32(sampleRate))
        wavData.append(Self.le32(byteRate))
        wavData.append(Self.le16(blockAlign))
        wavData.append(Self.le16(bitsPerSample))
        wavData.append("data".data(using: .ascii)!)
        wavData.append(Self.le32(dataChunkSize))
        wavData.append(pcmData)
        return wavData
    }

    private static func le16(_ value: UInt16) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    private static func le32(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
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
                let chunk = String(trimmed[cursor..<splitIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !chunk.isEmpty {
                    chunks.append(chunk)
                }
                cursor = trimmed.index(after: splitIndex)
            } else {
                chunks.append(String(segment).trimmingCharacters(in: .whitespacesAndNewlines))
                cursor = candidateEnd
            }
        }

        return chunks.filter { !$0.isEmpty }
    }
}
