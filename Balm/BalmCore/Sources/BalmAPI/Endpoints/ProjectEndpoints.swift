import Foundation
import BalmModels

public enum ProjectEndpoints {
    public struct List: JiraEndpoint {
        public struct PagedResponse: Decodable, Sendable {
            public let values: [JiraProject]
        }

        public typealias Response = PagedResponse
        public init() {}

        public func makeRequest(cloudId: String) throws -> URLRequest {
            try JiraEndpointBuilder.get(
                host: .rest,
                cloudId: cloudId,
                path: "/project/search",
                queryItems: [
                    URLQueryItem(name: "maxResults", value: "100"),
                    URLQueryItem(name: "expand", value: "lead,description")
                ]
            )
        }
    }

    /// Up to 20 projects the signed-in user viewed most recently, most recent
    /// first. Jira returns a bare array here, not a page.
    public struct Recent: JiraEndpoint {
        public typealias Response = [JiraProject]
        public init() {}

        public func makeRequest(cloudId: String) throws -> URLRequest {
            try JiraEndpointBuilder.get(
                host: .rest,
                cloudId: cloudId,
                path: "/project/recent",
                queryItems: []
            )
        }
    }

    public struct Boards: JiraEndpoint {
        public struct PagedResponse: Decodable, Sendable {
            public let values: [JiraBoard]
            public let isLast: Bool?
        }

        public typealias Response = PagedResponse
        public let projectKeyOrId: String

        public init(projectKeyOrId: String) {
            self.projectKeyOrId = projectKeyOrId
        }

        public func makeRequest(cloudId: String) throws -> URLRequest {
            try JiraEndpointBuilder.get(
                host: .agile,
                cloudId: cloudId,
                path: "/board",
                queryItems: [
                    URLQueryItem(name: "projectKeyOrId", value: projectKeyOrId),
                    URLQueryItem(name: "maxResults", value: "50")
                ]
            )
        }
    }

    public struct Sprints: JiraEndpoint {
        public struct PagedResponse: Decodable, Sendable {
            public let values: [JiraSprint]
            public let isLast: Bool?
        }

        public typealias Response = PagedResponse
        public let boardID: Int
        public let states: [String]?

        public init(boardID: Int, states: [String]? = nil) {
            self.boardID = boardID
            self.states = states
        }

        public func makeRequest(cloudId: String) throws -> URLRequest {
            var items = [URLQueryItem(name: "maxResults", value: "50")]
            if let states {
                items.append(URLQueryItem(name: "state", value: states.joined(separator: ",")))
            }
            return try JiraEndpointBuilder.get(
                host: .agile,
                cloudId: cloudId,
                path: "/board/\(boardID)/sprint",
                queryItems: items
            )
        }
    }

    public struct Versions: JiraEndpoint {
        public typealias Response = [JiraVersion]
        public let projectKeyOrId: String

        public init(projectKeyOrId: String) {
            self.projectKeyOrId = projectKeyOrId
        }

        public func makeRequest(cloudId: String) throws -> URLRequest {
            try JiraEndpointBuilder.get(
                host: .rest,
                cloudId: cloudId,
                path: "/project/\(projectKeyOrId)/versions"
            )
        }
    }

    public struct Components: JiraEndpoint {
        public typealias Response = [JiraComponent]
        public let projectKeyOrId: String

        public init(projectKeyOrId: String) {
            self.projectKeyOrId = projectKeyOrId
        }

        public func makeRequest(cloudId: String) throws -> URLRequest {
            try JiraEndpointBuilder.get(
                host: .rest,
                cloudId: cloudId,
                path: "/project/\(projectKeyOrId)/components"
            )
        }
    }

    /// GET /rest/api/3/field — used to discover the tenant-specific Sprint
    /// custom field id (its `schema.custom` is the greenhopper sprint marker).
    /// Custom field ids vary per Jira site, so we never hardcode one.
    public struct Fields: JiraEndpoint {
        public struct Field: Decodable, Sendable {
            public let id: String
            public let name: String?
            public let schema: Schema?
            public struct Schema: Decodable, Sendable {
                public let custom: String?
            }
        }

        public typealias Response = [Field]
        public init() {}

        public func makeRequest(cloudId: String) throws -> URLRequest {
            try JiraEndpointBuilder.get(
                host: .rest,
                cloudId: cloudId,
                path: "/field"
            )
        }
    }
}
