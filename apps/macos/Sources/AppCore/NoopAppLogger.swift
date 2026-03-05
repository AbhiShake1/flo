import Foundation

public final class NoopAppLogger: AppLogger {
    public init() {}

    public func info(_ message: String) {}

    public func error(_ message: String) {}
}
