import Foundation
import Infrastructure

public enum VoiceCatalog {
    public static let openAISupportedVoices: [String] = [
        "alloy",
        "ash",
        "ballad",
        "coral",
        "echo",
        "fable",
        "onyx",
        "nova",
        "sage",
        "shimmer"
    ]

    public static let geminiSupportedVoices: [String] = [
        "Kore",
        "Puck",
        "Aoede",
        "Leda",
        "Orus",
        "Zephyr"
    ]

    public static func supportedVoices(for provider: AIProvider) -> [String] {
        switch provider {
        case .openai:
            return openAISupportedVoices
        case .gemini:
            return geminiSupportedVoices
        }
    }

    public static let speedRange: ClosedRange<Double> = 0.25...4.0
}
