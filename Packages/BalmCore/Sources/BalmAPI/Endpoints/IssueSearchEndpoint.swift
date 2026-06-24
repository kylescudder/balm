import Foundation
import BalmModels

public enum IssueEndpoints {
    public struct Search: JiraEndpoint {
        public struct PagedResponse: Decodable, Sendable {
            public let issues: [RawJiraIssue]
            public let nextPageToken: String?
            public let isLast: Bool?
            public let total: Int?
            /// Field-id → display-name map from `expand=names`.
            public let names: [String: String]?
        }

        public typealias Response = PagedResponse
        public let jql: String
        public let fields: [String]
        public let nextPageToken: String?
        public let maxResults: Int

        public init(
            jql: String,
            fields: [String] = JiraIssue.defaultFields,
            nextPageToken: String? = nil,
            maxResults: Int = 100
        ) {
            self.jql = jql
            self.fields = fields
            self.nextPageToken = nextPageToken
            self.maxResults = maxResults
        }

        public func makeRequest(cloudId: String) throws -> URLRequest {
            var items: [URLQueryItem] = [
                URLQueryItem(name: "jql", value: jql),
                URLQueryItem(name: "fields", value: fields.joined(separator: ",")),
                URLQueryItem(name: "expand", value: "names"),
                URLQueryItem(name: "maxResults", value: String(maxResults))
            ]
            if let token = nextPageToken {
                items.append(URLQueryItem(name: "nextPageToken", value: token))
            }
            return try JiraEndpointBuilder.get(
                host: .rest,
                cloudId: cloudId,
                path: "/search/jql",
                queryItems: items
            )
        }
    }

    public struct Get: JiraEndpoint {
        public typealias Response = RawJiraIssue
        public let issueKey: String
        public let expand: [String]
        public let fields: [String]

        public init(
            issueKey: String,
            expand: [String] = [],
            fields: [String] = JiraIssue.defaultFields
        ) {
            self.issueKey = issueKey
            self.expand = expand
            self.fields = fields
        }

        public func makeRequest(cloudId: String) throws -> URLRequest {
            var items: [URLQueryItem] = [
                URLQueryItem(name: "fields", value: fields.joined(separator: ","))
            ]
            if !expand.isEmpty {
                items.append(URLQueryItem(name: "expand", value: expand.joined(separator: ",")))
            }
            return try JiraEndpointBuilder.get(
                host: .rest,
                cloudId: cloudId,
                path: "/issue/\(issueKey)",
                queryItems: items
            )
        }
    }

    public struct Transitions: JiraEndpoint {
        public struct TransitionsResponse: Decodable, Sendable {
            public let transitions: [JiraTransition]
        }

        public typealias Response = TransitionsResponse
        public let issueKey: String

        public init(issueKey: String) { self.issueKey = issueKey }

        public func makeRequest(cloudId: String) throws -> URLRequest {
            try JiraEndpointBuilder.get(
                host: .rest,
                cloudId: cloudId,
                path: "/issue/\(issueKey)/transitions"
            )
        }
    }
}
