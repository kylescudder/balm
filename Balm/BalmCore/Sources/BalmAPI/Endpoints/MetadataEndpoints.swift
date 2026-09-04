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
            public let required: Bool?
            public let schema: Schema?
            public let allowedValues: [AllowedValue]?

            /// The canonical field id, preferring `fieldId` over the legacy `key`.
            public var identifier: String? { fieldId ?? key }

            /// True when the field stores a list (e.g. the system `components`
            /// field, `type == "array"`) rather than a single option (e.g. a
            /// custom single-select "Component", `type == "option"`).
            public var isMultiValue: Bool { schema?.type == "array" }

            /// True when the field holds selectable option(s) rather than free
            /// text, a user or a date. Guards the loose name match below, so a
            /// text field like "Component notes" can't be mistaken for the
            /// component picker.
            public var isOptionShaped: Bool {
                schema?.type == "option" || schema?.type == "array"
            }

            public struct Schema: Decodable, Sendable {
                public let type: String?
                public let system: String?
                public let custom: String?
                public let customId: Int?
            }
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

        /// The component field as a full `FieldMeta` — the create form needs the
        /// field id, option ids, arity and required flag, not just the JQL
        /// labels `resolveComponentField` returns.
        ///
        /// Tenants do not name this field consistently, and it varies *by issue
        /// type* within one project: MP5 calls it "Component"
        /// (`customfield_10312`) on Task but "Internal Component"
        /// (`customfield_11906`) on Internal Improvement. An exact-name rule
        /// misses the latter, which silently hides the picker and leaves Jira to
        /// reject the create with "Internal Component is required". So fall back
        /// to a name that merely *contains* "component".
        public static func componentField(from fields: [FieldMeta]) -> FieldMeta? {
            fields
                .compactMap { field in componentRank(field).map { (rank: $0, field: field) } }
                .min(by: preferred)?
                .field
        }

        /// How good a component-field candidate this is — lower is better,
        /// `nil` means "not one".
        ///
        /// The loose `contains` tiers are restricted to option-shaped fields so
        /// a text field like "Component notes" or a user field like "Component
        /// owner" can't be picked, and rank required above optional: a required
        /// field is the one that blocks the create, so it is the one the form
        /// most needs to show. An exact name needs no shape guard — it is
        /// unambiguous, and some tenants return it without a schema.
        private static func componentRank(_ field: FieldMeta) -> Int? {
            guard let id = field.identifier else { return nil }
            if id == "components" { return 0 }
            guard id.hasPrefix("customfield_") else { return nil }
            let name = (field.name ?? "").lowercased()
            if name == "component" || name == "components" { return 1 }
            guard name.contains("component"), field.isOptionShaped else { return nil }
            return field.required == true ? 2 : 3
        }

        /// Tie-break equal ranks deterministically: the shorter name is the
        /// plainer one, then field id so the choice never depends on the order
        /// Jira happened to return.
        private static func preferred(
            _ lhs: (rank: Int, field: FieldMeta),
            _ rhs: (rank: Int, field: FieldMeta)
        ) -> Bool {
            if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
            let lhsName = lhs.field.name ?? ""
            let rhsName = rhs.field.name ?? ""
            if lhsName.count != rhsName.count { return lhsName.count < rhsName.count }
            return (lhs.field.identifier ?? "") < (rhs.field.identifier ?? "")
        }

        /// The component field's JQL name (`component` or `cf[<id>]`) and its
        /// allowed value labels. Shares `componentField`'s selection rule, so
        /// the filter path and the create form can never disagree about which
        /// field holds components.
        public static func resolveComponentField(
            from fields: [FieldMeta]
        ) -> (jqlField: String, values: [String])? {
            guard let field = componentField(from: fields), let id = field.identifier else { return nil }
            let values = (field.allowedValues ?? []).compactMap(\.label).filter { !$0.isEmpty }
            if id == "components" { return ("component", values) }
            guard id.hasPrefix("customfield_") else { return nil }
            return ("cf[\(id.dropFirst("customfield_".count))]", values)
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
