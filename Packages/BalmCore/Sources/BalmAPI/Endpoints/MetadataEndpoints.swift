import Foundation
import BalmModels

public enum MetadataEndpoints {
    /// GET /rest/api/3/priority — list global priorities.
    public struct Priorities: JiraEndpoint {
        public typealias Response = [JiraPriority]
        public init() {}
        public func makeRequest(cloudId: String) throws -> URLRequest {
            try JiraEndpointBuilder.get(host: .rest, cloudId: cloudId, path: "/priority")
        }
    }

    /// GET /rest/api/3/issuetype/project?projectId=... — issue types for a project.
    public struct ProjectIssueTypes: JiraEndpoint {
        public typealias Response = [JiraIssueType]
        public let projectID: String
        public init(projectID: String) { self.projectID = projectID }
        public func makeRequest(cloudId: String) throws -> URLRequest {
            try JiraEndpointBuilder.get(
                host: .rest,
                cloudId: cloudId,
                path: "/issuetype/project",
                queryItems: [URLQueryItem(name: "projectId", value: projectID)]
            )
        }
    }

    /// GET /rest/api/3/label?startAt=0 — paginated global label index.
    /// Useful for label autocomplete.
    public struct Labels: JiraEndpoint {
        public struct PagedResponse: Decodable, Sendable {
            public let values: [String]
            public let isLast: Bool?
        }
        public typealias Response = PagedResponse
        public init() {}
        public func makeRequest(cloudId: String) throws -> URLRequest {
            try JiraEndpointBuilder.get(
                host: .rest,
                cloudId: cloudId,
                path: "/label",
                queryItems: [URLQueryItem(name: "maxResults", value: "1000")]
            )
        }
    }
}
