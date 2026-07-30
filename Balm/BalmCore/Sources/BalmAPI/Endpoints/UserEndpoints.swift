import Foundation
import BalmModels

public enum UserEndpoints {
    public struct Myself: JiraEndpoint {
        public typealias Response = JiraUser
        public init() {}
        public func makeRequest(cloudId: String) throws -> URLRequest {
            try JiraEndpointBuilder.get(host: .rest, cloudId: cloudId, path: "/myself")
        }
    }

    public struct ProjectUsers: JiraEndpoint {
        public typealias Response = [JiraUser]
        public let projectKey: String
        public init(projectKey: String) { self.projectKey = projectKey }

        public func makeRequest(cloudId: String) throws -> URLRequest {
            try JiraEndpointBuilder.get(
                host: .rest,
                cloudId: cloudId,
                path: "/user/assignable/search",
                queryItems: [
                    URLQueryItem(name: "project", value: projectKey),
                    URLQueryItem(name: "maxResults", value: "1000")
                ]
            )
        }
    }

    /// Typeahead for @mention autocomplete — assignable users in the project
    /// whose name/email matches `query`. Capped small for a snappy dropdown.
    public struct MentionSearch: JiraEndpoint {
        public typealias Response = [JiraUser]
        public let projectKey: String
        public let query: String
        public init(projectKey: String, query: String) {
            self.projectKey = projectKey
            self.query = query
        }

        public func makeRequest(cloudId: String) throws -> URLRequest {
            try JiraEndpointBuilder.get(
                host: .rest,
                cloudId: cloudId,
                path: "/user/assignable/search",
                queryItems: [
                    URLQueryItem(name: "project", value: projectKey),
                    URLQueryItem(name: "query", value: query),
                    URLQueryItem(name: "maxResults", value: "8")
                ]
            )
        }
    }
}
