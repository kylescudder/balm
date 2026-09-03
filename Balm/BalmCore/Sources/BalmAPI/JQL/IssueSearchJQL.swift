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
    /// The JQL for `query`, or `nil` when the query has nothing searchable.
    public static func make(query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var clauses: [String] = []
        let terms = searchTerms(trimmed)
        if !terms.isEmpty {
            clauses.append("text ~ \"\(terms.joined(separator: " "))*\"")
        }
        if let key = IssueKey.fullKey(trimmed) {
            // Keys are validated to `PROJ-123` shape, so no quoting needed.
            clauses.insert("issuekey = \(key)", at: 0)
        }
        guard !clauses.isEmpty else { return nil }

        let expr = clauses.count > 1 ? "(\(clauses.joined(separator: " OR ")))" : clauses[0]
        return "\(expr) order by updated DESC"
    }

    /// Jira passes the quoted string to Lucene as a query in its own right, so
    /// punctuation such as `>`, `(` or `-` becomes an operator or an empty token
    /// and the whole search matches nothing. Keep runs of letters and digits and
    /// split on everything else; single characters are dropped when longer
    /// terms exist, so "won't" does not turn into a match-everything `t*`.
    static func searchTerms(_ raw: String) -> [String] {
        let tokens = raw
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        let longer = tokens.filter { $0.count > 1 }
        return longer.isEmpty ? tokens : longer
    }
}
