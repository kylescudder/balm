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

    /// GET /rest/api/3/issue/createmeta/{projectIdOrKey}/issuetypes/{issueTypeId}
    /// — create-screen field metadata for one issue type. Used to resolve which
    /// field actually holds "components" for a project (the standard
    /// `components` field, or a tenant custom select like `customfield_10312`)
    /// and that field's allowed values.
    public struct CreateMetaFields: JiraEndpoint {
        public struct Response: Decodable, Sendable {
            public let fields: [FieldMeta]
        }
        public struct FieldMeta: Decodable, Sendable {
            public let fieldId: String?
            public let key: String?
            public let name: String?
            public let allowedValues: [AllowedValue]?

            /// The canonical field id, preferring `fieldId` over the legacy `key`.
            public var identifier: String? { fieldId ?? key }
        }
        public struct AllowedValue: Decodable, Sendable {
            public let id: String?
            public let name: String?
            public let value: String?

            /// Display text — standard options use `name`, custom select options `value`.
            public var label: String? { name ?? value }
        }

        public let projectIdOrKey: String
        public let issueTypeId: String
        public init(projectIdOrKey: String, issueTypeId: String) {
            self.projectIdOrKey = projectIdOrKey
            self.issueTypeId = issueTypeId
        }
        public func makeRequest(cloudId: String) throws -> URLRequest {
            try JiraEndpointBuilder.get(
                host: .rest,
                cloudId: cloudId,
                path: "/issue/createmeta/\(projectIdOrKey)/issuetypes/\(issueTypeId)",
                queryItems: [URLQueryItem(name: "maxResults", value: "200")]
            )
        }

        /// Pick the component field out of a create-metadata field list,
        /// preferring the standard `components` field, else a custom select
        /// named "Component(s)". Returns its JQL field name (`component` or
        /// `cf[<id>]`) and the list of allowed value labels.
        public static func resolveComponentField(
            from fields: [FieldMeta]
        ) -> (jqlField: String, values: [String])? {
            func labels(_ field: FieldMeta) -> [String] {
                (field.allowedValues ?? []).compactMap(\.label).filter { !$0.isEmpty }
            }
            if let standard = fields.first(where: { $0.identifier == "components" }) {
                return ("component", labels(standard))
            }
            if let custom = fields.first(where: { field in
                guard let id = field.identifier, id.hasPrefix("customfield_") else { return false }
                let name = (field.name ?? "").lowercased()
                return name == "component" || name == "components"
            }), let id = custom.identifier {
                let number = id.dropFirst("customfield_".count)
                return ("cf[\(number)]", labels(custom))
            }
            return nil
        }

        /// Resolve the tenant's "Instance / Database" custom select from a
        /// create-metadata field list: its field id (authoritative and
        /// project-scoped — unlike a global `/field` name scan, which can hit a
        /// like-named field from another project) plus its full option list.
        /// `allowedValues` carries every configured option — uncapped and
        /// independent of which values happen to appear on loaded issues.
        public static func resolveInstanceField(
            from fields: [FieldMeta]
        ) -> (fieldId: String, values: [String])? {
            guard let field = fields.first(where: { field in
                guard let id = field.identifier, id.hasPrefix("customfield_") else { return false }
                return (field.name ?? "").localizedCaseInsensitiveContains("Instance")
            }), let id = field.identifier else { return nil }
            let values = (field.allowedValues ?? []).compactMap(\.label).filter { !$0.isEmpty }
            return (id, values)
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
