import Foundation
import BalmModels

public extension IssueEndpoints {
    /// POST /rest/api/3/issueLink — `{ type, inwardIssue, outwardIssue }`.
    /// Direction is encoded by which key sits in `inwardIssue` vs `outwardIssue`.
    /// Returns 201 with an empty body — caller should refresh issue detail.
    struct AddLink: JiraEndpoint {
        public typealias Response = EmptyResponse

        public let typeName: String
        public let inwardIssueKey: String
        public let outwardIssueKey: String

        public init(typeName: String, inwardIssueKey: String, outwardIssueKey: String) {
            self.typeName = typeName
            self.inwardIssueKey = inwardIssueKey
            self.outwardIssueKey = outwardIssueKey
        }

        public func makeRequest(cloudId: String) throws -> URLRequest {
            let url = try JiraEndpointBuilder.makeURL(
                host: .rest,
                cloudId: cloudId,
                path: "/issueLink"
            )
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let payload: [String: Any] = [
                "type": ["name": typeName],
                "inwardIssue": ["key": inwardIssueKey],
                "outwardIssue": ["key": outwardIssueKey]
            ]
            req.httpBody = try JSONSerialization.data(withJSONObject: payload)
            return req
        }
    }

    /// DELETE /rest/api/3/issueLink/{linkID}.
    struct RemoveLink: JiraEndpoint {
        public typealias Response = EmptyResponse
        public let linkID: String

        public init(linkID: String) { self.linkID = linkID }

        public func makeRequest(cloudId: String) throws -> URLRequest {
            let url = try JiraEndpointBuilder.makeURL(
                host: .rest,
                cloudId: cloudId,
                path: "/issueLink/\(linkID)"
            )
            var req = URLRequest(url: url)
            req.httpMethod = "DELETE"
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            return req
        }
    }

    /// GET /rest/api/3/issue/picker?query=... — typeahead for issue keys.
    /// Returns sections grouped by source (history, current search).
    struct PickerSuggest: JiraEndpoint {
        public struct Response: Decodable, Sendable {
            public let sections: [Section]

            public struct Section: Decodable, Sendable {
                public let id: String?
                public let label: String?
                public let issues: [Issue]?
            }

            public struct Issue: Decodable, Sendable {
                public let key: String
                public let summaryText: String?
                public let img: String?
            }
        }

        public let query: String
        public let projectKeyFilter: String?

        public init(query: String, projectKeyFilter: String? = nil) {
            self.query = query
            self.projectKeyFilter = projectKeyFilter
        }

        public func makeRequest(cloudId: String) throws -> URLRequest {
            var items: [URLQueryItem] = [URLQueryItem(name: "query", value: query)]
            if let projectKeyFilter {
                items.append(URLQueryItem(name: "currentProjectId", value: projectKeyFilter))
            }
            return try JiraEndpointBuilder.get(
                host: .rest,
                cloudId: cloudId,
                path: "/issue/picker",
                queryItems: items
            )
        }
    }
}

public extension MetadataEndpoints {
    /// GET /rest/api/3/issueLinkType — global list of link types.
    struct IssueLinkTypes: JiraEndpoint {
        public struct Response: Decodable, Sendable {
            public let issueLinkTypes: [JiraIssueLink.LinkType]
        }
        public typealias ResponseType = Response  // (no longer needed; alias unused)
        public init() {}
        public func makeRequest(cloudId: String) throws -> URLRequest {
            try JiraEndpointBuilder.get(host: .rest, cloudId: cloudId, path: "/issueLinkType")
        }
    }
}
