import Foundation
import BalmModels

/// Endpoints backing the Phase 1 in-app notification poll. Jira Cloud has no
/// public bell-notification API, so this synthesizes one client-side from the
/// enhanced search endpoint: `assignee/reporter/watcher = currentUser()` issues
/// updated within a rolling window, expanded with `changelog` and comments.
/// See `NotificationSyncWindow` (JQL/window) and `NotificationDiffer` (derivation).
public enum NotificationEndpoints {
    public struct Search: JiraEndpoint {
        public struct PagedResponse: Decodable, Sendable {
            public let issues: [RawNotificationIssue]
            public let nextPageToken: String?
            public let isLast: Bool?
        }

        public typealias Response = PagedResponse

        /// Fields requested on every poll — comment gives recent comments,
        /// the rest are what a notification row needs to render.
        public static let fields: [String] = [
            "summary", "status", "assignee", "reporter", "created", "updated", "comment"
        ]

        public let jql: String
        public let maxResults: Int
        public let nextPageToken: String?

        public init(jql: String, maxResults: Int = 50, nextPageToken: String? = nil) {
            self.jql = jql
            self.maxResults = maxResults
            self.nextPageToken = nextPageToken
        }

        public func makeRequest(cloudId: String) throws -> URLRequest {
            var items: [URLQueryItem] = [
                URLQueryItem(name: "jql", value: jql),
                URLQueryItem(name: "fields", value: Self.fields.joined(separator: ",")),
                URLQueryItem(name: "expand", value: "changelog"),
                URLQueryItem(name: "maxResults", value: String(maxResults))
            ]
            if let nextPageToken {
                items.append(URLQueryItem(name: "nextPageToken", value: nextPageToken))
            }
            return try JiraEndpointBuilder.get(
                host: .rest,
                cloudId: cloudId,
                path: "/search/jql",
                queryItems: items
            )
        }
    }

    /// GET /issue/{key}/comment — used as a fallback when the embedded
    /// `fields.comment` page on `Search` is truncated (see
    /// `NotificationDiffer.truncatedCommentIssueIDs(in:)`). Ordered newest
    /// first so the most recent comments — the ones most likely to be new —
    /// are the ones that fit within `maxResults`.
    public struct RecentComments: JiraEndpoint {
        public typealias Response = RawNotificationIssue.CommentsPage
        public let issueKey: String
        public let maxResults: Int

        public init(issueKey: String, maxResults: Int = 100) {
            self.issueKey = issueKey
            self.maxResults = maxResults
        }

        public func makeRequest(cloudId: String) throws -> URLRequest {
            try JiraEndpointBuilder.get(
                host: .rest,
                cloudId: cloudId,
                path: "/issue/\(issueKey)/comment",
                queryItems: [
                    URLQueryItem(name: "orderBy", value: "-created"),
                    URLQueryItem(name: "maxResults", value: String(maxResults))
                ]
            )
        }
    }

    // MARK: - Cross-device read-state sync
    //
    // Persists `InboxReadState` to a per-user Jira user property so read/unread
    // marks converge across devices (see `InboxStore.syncNow`/`schedulePushReadState`).
    // There's no bulk "notifications" concept in Jira itself — this is Balm's
    // own synced document, keyed under `readStatePropertyKey`.

    /// Per-user property key backing cross-device read-state sync. Values are
    /// opaque per-user key/value storage capped at 32 KB by Jira;
    /// `InboxReadState.readIdsCap` keeps this comfortably under that ceiling.
    public static let readStatePropertyKey = "balm-inbox-read-state"

    /// GET /user/properties/{key}?accountId=... — 404 means the property was
    /// never set; callers should treat that as an empty `InboxReadState`, not
    /// an error (see `InboxStore.syncNow`).
    public struct GetReadState: JiraEndpoint {
        public struct PropertyEnvelope: Decodable, Sendable {
            public let key: String
            public let value: InboxReadState
        }

        public typealias Response = PropertyEnvelope
        public let accountId: String

        public init(accountId: String) {
            self.accountId = accountId
        }

        public func makeRequest(cloudId: String) throws -> URLRequest {
            try JiraEndpointBuilder.get(
                host: .rest,
                cloudId: cloudId,
                path: "/user/properties/\(NotificationEndpoints.readStatePropertyKey)",
                queryItems: [URLQueryItem(name: "accountId", value: accountId)]
            )
        }
    }

    /// PUT /user/properties/{key}?accountId=... with the raw `InboxReadState`
    /// JSON as the body (200 updated / 201 created, empty body either way).
    /// `JiraEndpointBuilder.json` has no query-item parameter, so this is
    /// built by hand — same pattern as `IssueMutationEndpoints`.
    public struct PutReadState: JiraEndpoint {
        public typealias Response = EmptyResponse
        public let accountId: String
        public let state: InboxReadState

        public init(accountId: String, state: InboxReadState) {
            self.accountId = accountId
            self.state = state
        }

        public func makeRequest(cloudId: String) throws -> URLRequest {
            let url = try JiraEndpointBuilder.makeURL(
                host: .rest,
                cloudId: cloudId,
                path: "/user/properties/\(NotificationEndpoints.readStatePropertyKey)",
                queryItems: [URLQueryItem(name: "accountId", value: accountId)]
            )
            var req = URLRequest(url: url)
            req.httpMethod = "PUT"
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(state)
            return req
        }
    }

    // MARK: - Raw wire types
    //
    // Dedicated to this poll rather than reusing `RawJiraIssue`/`RawJiraChangelogPage`:
    // those carry `JiraUserSummary` (no `accountId`) and changelog items with only
    // display strings, but the diff needs the raw `to`/`from` accountId on the
    // assignee item and the author `accountId` on every history/comment to
    // suppress self-authored activity. `RawJiraIssue.init(from:)` is also fragile
    // (scans customfields) — not worth entangling with a second decode shape.

    public struct RawNotificationIssue: Decodable, Sendable {
        public let id: String
        public let key: String
        public let fields: Fields
        /// Present because the request always sends `expand=changelog`.
        public let changelog: Changelog?

        public struct Fields: Decodable, Sendable {
            public let summary: String
            public let status: Status?
            public let assignee: User?
            public let reporter: User?
            public let created: Date?
            public let updated: Date?
            public let comment: CommentsPage?
        }

        public struct Status: Decodable, Sendable {
            public let name: String
        }

        public struct User: Decodable, Sendable {
            public let accountId: String
            public let displayName: String
        }

        public struct CommentsPage: Decodable, Sendable {
            public let comments: [Comment]
            public let total: Int?
        }

        public struct Comment: Decodable, Sendable {
            public let id: String
            public let author: User
            public let created: Date?
            /// Tolerant object-or-null decode (ADF body) — parsed lazily by BalmADF.
            public let body: ADFEnvelope?
        }

        public struct Changelog: Decodable, Sendable {
            public let histories: [History]
            public let total: Int?
        }

        public struct History: Decodable, Sendable {
            public let id: String
            public let author: User
            public let created: Date?
            public let items: [Item]
        }

        public struct Item: Decodable, Sendable {
            public let field: String
            public let fieldId: String?
            /// Raw value (e.g. an accountId for `assignee`, a status id for `status`).
            public let from: String?
            public let to: String?
            /// Human-readable value (e.g. a display name / status name).
            public let fromString: String?
            public let toString: String?
        }
    }
}
