import Foundation
import BalmModels

public extension IssueEndpoints {
    /// Fetches a single issue with everything required for the detail screen:
    /// description (ADF), comments, attachments, issue links, and the full
    /// changelog. Mirrors the web `/api/issues/[issueKey]/details` aggregate.
    struct GetDetail: JiraEndpoint {
        public typealias Response = RawJiraIssue

        public let issueKey: String

        public init(issueKey: String) {
            self.issueKey = issueKey
        }

        public func makeRequest(cloudId: String) throws -> URLRequest {
            try JiraEndpointBuilder.get(
                host: .rest,
                cloudId: cloudId,
                path: "/issue/\(issueKey)",
                queryItems: [
                    URLQueryItem(name: "fields", value: "*all"),
                    URLQueryItem(name: "expand", value: "changelog,renderedFields,names"),
                    URLQueryItem(name: "properties", value: "*all")
                ]
            )
        }
    }
}
