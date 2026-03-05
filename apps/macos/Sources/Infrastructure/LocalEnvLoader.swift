import Foundation

public enum LocalEnvLoader {
    private static let envFilenames = [".env.local", ".env"]

    public static func mergedEnvironment(
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        cwd: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        bundleResourceURL: URL? = Bundle.main.resourceURL,
        executableURL: URL? = Bundle.main.executableURL
    ) -> [String: String] {
        var merged = processEnvironment

        if let explicitPath = nonEmpty(processEnvironment["FLO_ENV_FILE"]) {
            applyEnvironmentFile(at: URL(fileURLWithPath: explicitPath), to: &merged)
        }

        let directories = candidateDirectories(
            cwd: cwd,
            bundleResourceURL: bundleResourceURL,
            executableURL: executableURL
        )
        for directory in directories {
            for filename in envFilenames {
                applyEnvironmentFile(at: directory.appendingPathComponent(filename), to: &merged)
            }
        }

        return merged
    }

    private static func candidateDirectories(
        cwd: URL,
        bundleResourceURL: URL?,
        executableURL: URL?
    ) -> [URL] {
        var directories: [URL] = []
        var seenPaths = Set<String>()

        appendUniqueDirectory(cwd, to: &directories, seenPaths: &seenPaths)

        if let bundleResourceURL {
            appendUniqueDirectory(bundleResourceURL, to: &directories, seenPaths: &seenPaths)
        }

        if let executableURL {
            var current = executableURL.deletingLastPathComponent()
            for _ in 0..<8 {
                appendUniqueDirectory(current, to: &directories, seenPaths: &seenPaths)
                let parent = current.deletingLastPathComponent()
                if parent.path == current.path {
                    break
                }
                current = parent
            }
        }

        return directories
    }

    private static func appendUniqueDirectory(
        _ directory: URL,
        to directories: inout [URL],
        seenPaths: inout Set<String>
    ) {
        let standardized = directory.standardizedFileURL.path
        if !seenPaths.insert(standardized).inserted {
            return
        }
        directories.append(directory.standardizedFileURL)
    }

    private static func applyEnvironmentFile(at url: URL, to merged: inout [String: String]) {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return
        }

        for line in content.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            guard let separator = trimmed.firstIndex(of: "=") else {
                continue
            }

            let key = String(trimmed[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            var value = String(trimmed[trimmed.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)

            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                value.removeFirst()
                value.removeLast()
            }

            if !key.isEmpty && merged[key] == nil {
                merged[key] = value
            }
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
