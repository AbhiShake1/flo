import AppCore
import AVFoundation
import Foundation
import Speech

public final class AVAudioEngineCaptureService: NSObject, SpeechCaptureService, @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let fileLock = NSLock()

    private var outputFile: AVAudioFile?
    private var outputURL: URL?
    private var levelHandler: ((Float) -> Void)?
    private var transcriptHandler: ((String) -> Void)?
    private var isCapturing = false
    private var speechRequest: SFSpeechAudioBufferRecognitionRequest?
    private var speechTask: SFSpeechRecognitionTask?
    private var latestTranscript = ""

    public override init() {
        super.init()
    }

    public func startCapture(levelHandler: @escaping (Float) -> Void) throws {
        try startCapture(levelHandler: levelHandler, transcriptHandler: nil)
    }

    public func startCapture(
        levelHandler: @escaping (Float) -> Void,
        transcriptHandler: @escaping (String) -> Void
    ) throws {
        try startCapture(levelHandler: levelHandler, transcriptHandler: Optional(transcriptHandler))
    }

    private func startCapture(
        levelHandler: @escaping (Float) -> Void,
        transcriptHandler: ((String) -> Void)?
    ) throws {
        cancelCapture()

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("flo-recording-\(UUID().uuidString)")
            .appendingPathExtension("wav")

        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: inputFormat.sampleRate,
            channels: inputFormat.channelCount,
            interleaved: false
        ) ?? inputFormat

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: targetFormat.sampleRate,
            AVNumberOfChannelsKey: targetFormat.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]

        let outputFile = try AVAudioFile(forWriting: outputURL, settings: outputSettings)
        if let transcriptHandler {
            try configureSpeechRecognition(transcriptHandler: transcriptHandler)
        } else {
            clearSpeechRecognitionState()
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: targetFormat) { [weak self] buffer, _ in
            guard let self else {
                return
            }

            self.fileLock.lock()
            defer { self.fileLock.unlock() }

            do {
                try outputFile.write(from: buffer)
            } catch {
                // Best effort write; failure will be surfaced on stop by size validation.
            }

            self.speechRequest?.append(buffer)

            let level = Self.computeLevel(from: buffer)
            DispatchQueue.main.async {
                self.levelHandler?(level)
            }
        }

        engine.prepare()
        try engine.start()

        self.outputFile = outputFile
        self.outputURL = outputURL
        self.levelHandler = levelHandler
        self.transcriptHandler = transcriptHandler
        self.isCapturing = true
    }

    public func stopCapture() throws -> URL {
        guard isCapturing, let outputURL else {
            throw FloError.emptyAudio
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        speechRequest?.endAudio()

        isCapturing = false
        self.outputFile = nil
        self.levelHandler = nil
        clearSpeechRecognitionState()
        self.outputURL = nil

        let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let fileSize = (attributes[.size] as? NSNumber)?.intValue ?? 0
        if fileSize < 512 {
            throw FloError.emptyAudio
        }

        return outputURL
    }

    public func cancelCapture() {
        if isCapturing {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }

        speechRequest?.endAudio()
        clearSpeechRecognitionState()

        if let outputURL {
            try? FileManager.default.removeItem(at: outputURL)
        }

        outputFile = nil
        outputURL = nil
        levelHandler = nil
        transcriptHandler = nil
        isCapturing = false
    }

    private func configureSpeechRecognition(
        transcriptHandler: @escaping (String) -> Void
    ) throws {
        try ensureSpeechRecognitionPermission()
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current), recognizer.isAvailable else {
            throw FloError.network("Live speech recognition is unavailable on this device.")
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false

        latestTranscript = ""
        self.transcriptHandler = transcriptHandler
        speechRequest = request
        speechTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else {
                return
            }

            if let result {
                let candidate = result.bestTranscription.formattedString
                if !candidate.isEmpty, candidate != self.latestTranscript {
                    self.latestTranscript = candidate
                    DispatchQueue.main.async {
                        self.transcriptHandler?(candidate)
                    }
                }
            }

            if error != nil {
                self.clearSpeechRecognitionState(keepHandler: true)
            }
        }
    }

    private func ensureSpeechRecognitionPermission() throws {
        guard hasSpeechRecognitionUsageDescription() else {
            throw FloError.permissionDenied("Speech Recognition (missing NSSpeechRecognitionUsageDescription)")
        }

        let current = SFSpeechRecognizer.authorizationStatus()
        switch current {
        case .authorized:
            return
        case .notDetermined:
            let resolved = requestSpeechRecognitionPermission()
            guard resolved == .authorized else {
                throw FloError.permissionDenied("Speech Recognition")
            }
        case .denied, .restricted:
            throw FloError.permissionDenied("Speech Recognition")
        @unknown default:
            throw FloError.permissionDenied("Speech Recognition")
        }
    }

    private func requestSpeechRecognitionPermission() -> SFSpeechRecognizerAuthorizationStatus {
        var status = SFSpeechRecognizer.authorizationStatus()
        let semaphore = DispatchSemaphore(value: 0)
        SFSpeechRecognizer.requestAuthorization { resolved in
            status = resolved
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 5)
        return status
    }

    private func hasSpeechRecognitionUsageDescription() -> Bool {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription") as? String else {
            return false
        }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func clearSpeechRecognitionState(keepHandler: Bool = false) {
        speechTask?.cancel()
        speechTask = nil
        speechRequest = nil
        latestTranscript = ""
        if !keepHandler {
            transcriptHandler = nil
        }
    }

    private static func computeLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else {
            return 0
        }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else {
            return 0
        }

        var sumSquares: Float = 0
        for i in 0..<frameLength {
            let sample = channelData[i]
            sumSquares += sample * sample
        }

        let rms = sqrt(sumSquares / Float(frameLength))
        return min(1, max(0, rms * 3))
    }
}
