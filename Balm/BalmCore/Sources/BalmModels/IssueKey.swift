import Foundation

/// Parsing helpers for Jira issue-key shapes, shared by the search bar (which
/// jumps straight to a ticket) and the global-search JQL builder (which OR-s in
/// an exact `issuekey` clause). Kept pure and dependency-free so both the UI and
/// the API layer can reuse it — and so it's cheap to test.
public enum IssueKey {
    /// The full `PROJ-123` shape, upper-cased, or `nil` if `text` isn't one.
    public static func fullKey(_ text: String) -> String? {
        let upper = text.trimmingCharacters(in: .whitespaces).uppercased()
        let isKey = upper.range(of: #"^[A-Z][A-Z0-9]+-\d+$"#, options: .regularExpression) != nil
        return isKey ? upper : nil
    }

    /// Resolve `text` to a full issue key for direct look-up: a full `PROJ-123`
    /// is returned as-is (upper-cased); a bare number is assumed to belong to
    /// `projectKey` (so "123" → "PROJ-123"). Returns `nil` for anything else —
    /// i.e. free text that should go to a global search instead.
    public static func normalise(_ text: String, projectKey: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let key = fullKey(trimmed) { return key }
        if trimmed.range(of: #"^\d+$"#, options: .regularExpression) != nil {
            return "\(projectKey)-\(trimmed)"
        }
        return nil
    }
}
