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
        if provider == .gemini || provider == .google {
            return geminiSupportedVoices
        }
        return openAISupportedVoices
    }

    public static let speedRange: ClosedRange<Double> = 0.25...4.0
}
