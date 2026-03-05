import AppCore
import Foundation

public final class NoopDictationRewriteService: DictationRewriteService, @unchecked Sendable {
    public init() {}

    public func rewrite(
        transcript: String,
        authToken: String,
        preferences: DictationRewritePreferences
    ) async throws -> String {
        _ = authToken
        _ = preferences
        return transcript
    }
}
