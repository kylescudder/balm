import Foundation

public enum JiraError: Error, Sendable, Equatable {
    case urlConstruction(path: String)
    case http(status: Int, body: String?)
    case decoding(String)
    case unauthenticated
    case cancelled
    case missingSprint
}

extension JiraError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .urlConstruction(let p): return "Could not build URL for path \(p)."
        case .http(let s, let b): return "Jira API responded \(s)\(b.map { ": \($0)" } ?? "")."
        case .decoding(let m): return "Jira API response decoding failed: \(m)."
        case .unauthenticated: return "Not signed in to Jira."
        case .cancelled: return "Request cancelled."
        case .missingSprint: return "Sprint filter is required."
        }
    }
}

public extension Error {
    /// True for every shape a cancelled request takes: Swift's
    /// `CancellationError`, URLSession's `URLError.cancelled` (whose description
    /// is the bare word "cancelled"), and `JiraError.cancelled`. A cancelled
    /// request is never worth a toast.
    var isCancellation: Bool {
        if self is CancellationError { return true }
        if let urlError = self as? URLError, urlError.code == .cancelled { return true }
        if let jiraError = self as? JiraError, jiraError == .cancelled { return true }
        return false
    }
}
