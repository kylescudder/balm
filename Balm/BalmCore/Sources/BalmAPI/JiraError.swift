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
