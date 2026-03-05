import AppCore
import Foundation
import OSLog

public final class RedactingAppLogger: AppLogger {
    private let logger: Logger

    public init(subsystem: String = "com.flo.app", category: String = "runtime") {
        self.logger = Logger(subsystem: subsystem, category: category)
    }

    public func info(_ message: String) {
        logger.info("\(self.redact(message), privacy: .public)")
    }

    public func error(_ message: String) {
        logger.error("\(self.redact(message), privacy: .public)")
    }

    private func redact(_ raw: String) -> String {
        var output = raw

        let patterns: [String] = [
            "(?i)bearer\\s+[A-Za-z0-9._-]+",
            "(?i)(access|refresh)_token\\s*[:=]\\s*[A-Za-z0-9._-]+",
            "[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}"
        ]

        for pattern in patterns {
            output = output.replacingOccurrences(
                of: pattern,
                with: "[REDACTED]",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        return output
    }
}
