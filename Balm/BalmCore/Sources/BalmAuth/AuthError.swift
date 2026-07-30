import Foundation

public enum AuthError: Error, Sendable, Equatable {
    case userCancelled
    case stateMismatch
    case missingCode
    case missingTokenInResponse
    case invalidCallbackURL
    case noAccessibleResources
    case keychainFailure(OSStatus)
    case refreshFailed(reason: String)
    /// The rotating refresh token was rejected outright (revoked, expired, or
    /// invalidated by reuse detection) — no retry can succeed; the user must
    /// sign in again.
    case sessionExpired
    case configurationMissing(String)
    case http(status: Int, body: String?)
    case decoding(String)
}

extension AuthError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .userCancelled: return "Sign-in was cancelled."
        case .stateMismatch: return "Authentication state mismatch — possible CSRF; restart sign-in."
        case .missingCode: return "Atlassian returned no authorization code."
        case .missingTokenInResponse: return "Atlassian returned no access token."
        case .invalidCallbackURL: return "OAuth callback URL was malformed."
        case .noAccessibleResources: return "No Jira sites are accessible with this account."
        case .keychainFailure(let s): return "Keychain failure (\(s))."
        case .refreshFailed(let r): return "Token refresh failed: \(r)"
        case .sessionExpired: return "Your session has expired — please sign in again."
        case .configurationMissing(let k): return "OAuth configuration missing: \(k)"
        case .http(let s, let b): return "HTTP \(s)\(b.map { ": \($0)" } ?? "")"
        case .decoding(let m): return "Decoding failure: \(m)"
        }
    }
}
