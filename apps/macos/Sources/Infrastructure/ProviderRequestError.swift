import AppCore
import Foundation

public enum ProviderRequestError: LocalizedError, Sendable {
    case http(provider: AIProvider, operation: String, statusCode: Int, message: String)
    case transport(provider: AIProvider, operation: String, message: String)
    case invalidResponse(provider: AIProvider, operation: String, message: String)

    public var errorDescription: String? {
        switch self {
        case .http(let provider, let operation, let statusCode, let message):
            let details = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if details.isEmpty {
                return "\(provider.rawValue) \(operation) failed with HTTP \(statusCode)."
            }
            return "\(provider.rawValue) \(operation) failed with HTTP \(statusCode): \(details)"
        case .transport(let provider, let operation, let message):
            return "\(provider.rawValue) \(operation) transport error: \(message)"
        case .invalidResponse(let provider, let operation, let message):
            return "\(provider.rawValue) \(operation) invalid response: \(message)"
        }
    }

    public var isRetryableForFailover: Bool {
        switch self {
        case .http(_, _, let statusCode, _):
            return statusCode == 401 || statusCode == 403 || statusCode == 408 || statusCode == 409 ||
                statusCode == 425 || statusCode == 429 ||
                (500...599).contains(statusCode)
        case .transport:
            return true
        case .invalidResponse:
            return true
        }
    }
}

public enum ProviderFailoverClassifier {
    public static func shouldFailover(after error: Error) -> Bool {
        if let requestError = error as? ProviderRequestError {
            return requestError.isRetryableForFailover
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut,
                 .cannotFindHost,
                 .cannotConnectToHost,
                 .networkConnectionLost,
                 .dnsLookupFailed,
                 .notConnectedToInternet,
                 .internationalRoamingOff,
                 .callIsActive,
                 .dataNotAllowed,
                 .secureConnectionFailed,
                 .cannotLoadFromNetwork,
                 .resourceUnavailable:
                return true
            default:
                return false
            }
        }

        if let floError = error as? FloError {
            switch floError {
            case .network(let message):
                let normalized = message.lowercased()
                if normalized.contains("blocked host") {
                    return false
                }
                return true
            default:
                return false
            }
        }

        return false
    }
}
