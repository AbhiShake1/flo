import AppCore
import Foundation

public final class OpenAITranscriptionService: TranscriptionService, @unchecked Sendable {
    private struct SegmentPayload: Decodable {
        let avg_logprob: Double?
    }

    private struct ResponsePayload: Decodable {
        let text: String
        let confidence: Double?
        let segments: [SegmentPayload]?
    }

    private let configuration: FloConfiguration
    private let urlSession: URLSession

    public init(configuration: FloConfiguration, urlSession: URLSession = .shared) {
        self.configuration = configuration
        self.urlSession = urlSession
    }

    public func transcribe(audioFileURL: URL, authToken: String) async throws -> TranscriptResult {
        guard configuration.isAllowedHost(configuration.transcriptionURL) else {
            throw FloError.network("Blocked host for transcription endpoint.")
        }

        let boundary = "flo-boundary-\(UUID().uuidString)"
        let mimeType = audioFileURL.pathExtension.lowercased() == "wav" ? "audio/wav" : "audio/m4a"
        let body = try MultipartBuilder(boundary: boundary)
            .addField(name: "model", value: configuration.transcriptionModel)
            .addFile(
                name: "file",
                filename: audioFileURL.lastPathComponent,
                mimeType: mimeType,
                data: Data(contentsOf: audioFileURL)
            )
            .build()

        let startedAt = Date()
        var didRetryNetworkFailure = false
        var serverRetryCount = 0
        var backoffNanos: UInt64 = 300_000_000

        while true {
            do {
                var request = URLRequest(url: configuration.transcriptionURL)
                request.httpMethod = "POST"
                request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
                request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                request.httpBody = body

                let (data, response) = try await urlSession.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw FloError.network("Invalid response")
                }

                if (200..<300).contains(httpResponse.statusCode) {
                    let payload = try JSONDecoder().decode(ResponsePayload.self, from: data)
                    let elapsed = Int(Date().timeIntervalSince(startedAt) * 1000)
                    let requestID = httpResponse.value(forHTTPHeaderField: "x-request-id")
                    let confidence = payload.confidence ?? confidenceFromSegments(payload.segments)

                    return TranscriptResult(
                        text: payload.text.trimmingCharacters(in: .whitespacesAndNewlines),
                        requestID: requestID,
                        latencyMs: elapsed,
                        confidence: confidence
                    )
                }

                if shouldRetryServerStatus(httpResponse.statusCode), serverRetryCount < 2 {
                    serverRetryCount += 1
                    try await Task.sleep(nanoseconds: backoffNanos)
                    backoffNanos *= 2
                    continue
                }

                throw FloError.network(String(data: data, encoding: .utf8) ?? "Transcription request failed")
            } catch let urlError as URLError {
                if !didRetryNetworkFailure {
                    didRetryNetworkFailure = true
                    continue
                }
                throw FloError.network(urlError.localizedDescription)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw error
            }
        }
    }

    private func shouldRetryServerStatus(_ statusCode: Int) -> Bool {
        statusCode == 429 || (500...599).contains(statusCode)
    }

    private func confidenceFromSegments(_ segments: [SegmentPayload]?) -> Double? {
        guard let segments, !segments.isEmpty else {
            return nil
        }

        let values = segments.compactMap(\.avg_logprob)
        guard !values.isEmpty else {
            return nil
        }

        let averageLogProb = values.reduce(0, +) / Double(values.count)
        let bounded = min(0, max(-10, averageLogProb))
        return exp(bounded)
    }
}

private struct MultipartBuilder {
    let boundary: String
    private(set) var data = Data()

    init(boundary: String) {
        self.boundary = boundary
    }

    func addField(name: String, value: String) -> MultipartBuilder {
        var next = self
        next.data.append("--\(boundary)\r\n".data(using: .utf8)!)
        next.data.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        next.data.append("\(value)\r\n".data(using: .utf8)!)
        return next
    }

    func addFile(name: String, filename: String, mimeType: String, data fileData: Data) -> MultipartBuilder {
        var next = self
        next.data.append("--\(boundary)\r\n".data(using: .utf8)!)
        next.data.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        next.data.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        next.data.append(fileData)
        next.data.append("\r\n".data(using: .utf8)!)
        return next
    }

    func build() -> Data {
        var final = data
        final.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return final
    }
}
