import AppCore
import AVFoundation
import Foundation

public final class AVAudioRecorderCaptureService: NSObject, SpeechCaptureService, AVAudioRecorderDelegate, @unchecked Sendable {
    private var recorder: AVAudioRecorder?
    private var outputURL: URL?
    private var levelTimer: Timer?
    private var levelHandler: ((Float) -> Void)?

    public override init() {
        super.init()
    }

    public func startCapture(levelHandler: @escaping (Float) -> Void) throws {
        stopLevelMetering()

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("flo-recording-\(UUID().uuidString)")
            .appendingPathExtension("wav")

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]

        let recorder = try AVAudioRecorder(url: tempURL, settings: settings)
        recorder.delegate = self
        recorder.isMeteringEnabled = true

        guard recorder.record() else {
            throw FloError.emptyAudio
        }

        self.recorder = recorder
        self.outputURL = tempURL
        self.levelHandler = levelHandler
        startLevelMetering()
    }

    public func stopCapture() throws -> URL {
        guard let recorder, let outputURL else {
            throw FloError.emptyAudio
        }

        recorder.stop()
        stopLevelMetering()
        self.recorder = nil
        self.outputURL = nil

        let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let fileSize = (attributes[.size] as? NSNumber)?.intValue ?? 0
        if fileSize < 256 {
            throw FloError.emptyAudio
        }

        return outputURL
    }

    public func cancelCapture() {
        recorder?.stop()
        if let outputURL {
            try? FileManager.default.removeItem(at: outputURL)
        }
        recorder = nil
        outputURL = nil
        stopLevelMetering()
    }

    private func startLevelMetering() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let recorder else {
                return
            }
            recorder.updateMeters()
            let power = recorder.averagePower(forChannel: 0)
            let linear = pow(10, power / 20)
            self.levelHandler?(linear)
        }
    }

    private func stopLevelMetering() {
        levelTimer?.invalidate()
        levelTimer = nil
        levelHandler = nil
    }
}
