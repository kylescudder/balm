import Foundation

/// A single synthesized in-app notification (Phase 1: derived client-side by
/// polling `search/jql` and diffing changelog/comment activity — see
/// `NotificationDiffer` in BalmAPI). Domain layer stays dependency-free.
public struct BalmNotification: Codable, Sendable, Hashable, Identifiable {
    /// Dedupe id: `"<issueId>.changelog.<historyId>"` or `"<issueId>.comment.<commentId>"`.
    public var id: String
    public var kind: Kind
    public var issueKey: String
    public var issueSummary: String
    public var actorDisplayName: String?
    public var date: Date
    public var isRead: Bool

    public enum Kind: Codable, Sendable, Hashable {
        case assignedToYou
        case statusChanged(from: String?, to: String?)
        case commented(excerpt: String?)
        case mentioned(excerpt: String?)
        case fieldUpdated(field: String)
    }

    public init(
        id: String,
        kind: Kind,
        issueKey: String,
        issueSummary: String,
        actorDisplayName: String? = nil,
        date: Date,
        isRead: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.issueKey = issueKey
        self.issueSummary = issueSummary
        self.actorDisplayName = actorDisplayName
        self.date = date
        self.isRead = isRead
    }
}
