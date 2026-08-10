import Foundation
import BalmModels

/// Builds the JQL for a global, instance-wide free-text search — the query run
/// when the user presses ↵ in the search bar and the term isn't an exact key.
///
/// Deliberately *unscoped*: no `project`, `sprint`, or filter clause, so a match
/// surfaces from any project the user can see, whether or not it's cached or
/// within the current view's filters. Matches title, body, comments and other
/// text fields via the `text` master field, and OR-s in an exact `issuekey`
/// clause when the term looks like a key so an ID lands its own ticket too.
public enum IssueSearchJQL {
    /// The JQL for `query`, or `nil` when the query is blank.
    public static func make(query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var clauses = ["text ~ \"\(escape(trimmed))*\""]
        if let key = IssueKey.fullKey(trimmed) {
            // Keys are validated to `PROJ-123` shape, so no quoting needed.
            clauses.insert("issuekey = \(key)", at: 0)
        }

        let expr = clauses.count > 1 ? "(\(clauses.joined(separator: " OR ")))" : clauses[0]
        return "\(expr) order by updated DESC"
    }

    /// Escape the characters that would break out of a quoted JQL string. The
    /// trailing `*` wildcard is appended by `make`, never escaped.
    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
