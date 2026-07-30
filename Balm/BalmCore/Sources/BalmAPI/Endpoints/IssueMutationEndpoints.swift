import Foundation
import BalmModels

public extension IssueEndpoints {
    /// PUT /rest/api/3/issue/{key} with `{ fields: {...} }`.
    /// Callers build the typed field payload via the `IssueFieldPatch` helpers.
    struct UpdateFields: JiraEndpoint {
        public typealias Response = EmptyResponse
        public let issueKey: String
        public let fields: [String: AnyJSON]

        public init(issueKey: String, fields: [String: AnyJSON]) {
            self.issueKey = issueKey
            self.fields = fields
        }

        public func makeRequest(cloudId: String) throws -> URLRequest {
            let url = try JiraEndpointBuilder.makeURL(
                host: .rest,
                cloudId: cloudId,
                path: "/issue/\(issueKey)"
            )
            var req = URLRequest(url: url)
            req.httpMethod = "PUT"
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(["fields": fields])
            return req
        }
    }

    /// PUT /rest/api/3/issue/{key}/assignee with `{ accountId: string | null }`.
    /// Pass `nil` to unassign.
    struct Assign: JiraEndpoint {
        public typealias Response = EmptyResponse
        public let issueKey: String
        public let accountID: String?

        public init(issueKey: String, accountID: String?) {
            self.issueKey = issueKey
            self.accountID = accountID
        }

        public func makeRequest(cloudId: String) throws -> URLRequest {
            let url = try JiraEndpointBuilder.makeURL(
                host: .rest,
                cloudId: cloudId,
                path: "/issue/\(issueKey)/assignee"
            )
            var req = URLRequest(url: url)
            req.httpMethod = "PUT"
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            // JSONSerialization preserves an explicit NSNull for the null case.
            let payload: [String: Any] = ["accountId": accountID ?? NSNull()]
            req.httpBody = try JSONSerialization.data(withJSONObject: payload)
            return req
        }
    }

    /// POST /rest/api/3/issue/{key}/transitions with `{ transition: { id } }`.
    struct ApplyTransition: JiraEndpoint {
        public typealias Response = EmptyResponse
        public let issueKey: String
        public let transitionID: String

        public init(issueKey: String, transitionID: String) {
            self.issueKey = issueKey
            self.transitionID = transitionID
        }

        public func makeRequest(cloudId: String) throws -> URLRequest {
            let url = try JiraEndpointBuilder.makeURL(
                host: .rest,
                cloudId: cloudId,
                path: "/issue/\(issueKey)/transitions"
            )
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let payload: [String: Any] = ["transition": ["id": transitionID]]
            req.httpBody = try JSONSerialization.data(withJSONObject: payload)
            return req
        }
    }

    /// POST /rest/api/3/issue. Body shape is roughly `{ fields: {...} }`.
    /// Response carries the new issue's `id` and `key`.
    struct Create: JiraEndpoint {
        public struct CreateResponse: Decodable, Sendable {
            public let id: String
            public let key: String
        }

        public typealias Response = CreateResponse
        public let fields: [String: AnyJSON]

        public init(fields: [String: AnyJSON]) {
            self.fields = fields
        }

        public func makeRequest(cloudId: String) throws -> URLRequest {
            let url = try JiraEndpointBuilder.makeURL(
                host: .rest,
                cloudId: cloudId,
                path: "/issue"
            )
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(["fields": fields])
            return req
        }
    }

    /// POST /rest/agile/1.0/sprint/{sprintID}/issue with `{ issues: [issueKey] }`.
    /// Moves a single issue onto a sprint (agile API — not the customfield route).
    struct AddToSprint: JiraEndpoint {
        public typealias Response = EmptyResponse
        public let sprintID: Int
        public let issueKeys: [String]

        public init(sprintID: Int, issueKeys: [String]) {
            self.sprintID = sprintID
            self.issueKeys = issueKeys
        }

        public func makeRequest(cloudId: String) throws -> URLRequest {
            let url = try JiraEndpointBuilder.makeURL(
                host: .agile,
                cloudId: cloudId,
                path: "/sprint/\(sprintID)/issue"
            )
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: ["issues": issueKeys])
            return req
        }
    }

    /// POST /rest/agile/1.0/backlog/issue with `{ issues: [...] }`.
    /// Moves issues to the backlog (i.e., clears sprint assignment).
    struct MoveToBacklog: JiraEndpoint {
        public typealias Response = EmptyResponse
        public let issueKeys: [String]

        public init(issueKeys: [String]) { self.issueKeys = issueKeys }

        public func makeRequest(cloudId: String) throws -> URLRequest {
            let url = try JiraEndpointBuilder.makeURL(
                host: .agile,
                cloudId: cloudId,
                path: "/backlog/issue"
            )
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: ["issues": issueKeys])
            return req
        }
    }
}

/// Convenience builders for the `fields` payload on `UpdateFields` and `Create`.
/// Each returns a single `(name, AnyJSON)` pair the caller can merge into a dict.
public enum IssueFieldPatch {
    public static func priority(name: String) -> (String, AnyJSON) {
        ("priority", .object(["name": .string(name)]))
    }

    public static func dueDate(_ value: String?) -> (String, AnyJSON) {
        ("duedate", value.map { .string($0) } ?? .null)
    }

    public static func labels(_ labels: [String]) -> (String, AnyJSON) {
        ("labels", .array(labels.map { .string($0) }))
    }

    /// Components by name: `[{ "name": "api" }, ...]`.
    public static func components(names: [String]) -> (String, AnyJSON) {
        ("components", .array(names.map { .object(["name": .string($0)]) }))
    }

    /// Fix versions by id: `[{ "id": "10123" }, ...]`.
    public static func fixVersions(ids: [String]) -> (String, AnyJSON) {
        ("fixVersions", .array(ids.map { .object(["id": .string($0)]) }))
    }

    /// A select / multi-select field addressed by its create-metadata field id
    /// (the system `components` field or a custom select like
    /// `customfield_10312`), with options referenced by id — Jira accepts ids
    /// for both. `multiple` chooses the array vs single-object shape from the
    /// field's schema: `[{ "id": … }, …]` vs `{ "id": … }`.
    public static func optionField(
        _ fieldId: String,
        optionIDs: [String],
        multiple: Bool
    ) -> (String, AnyJSON) {
        let nodes = optionIDs.map { AnyJSON.object(["id": .string($0)]) }
        return multiple ? (fieldId, .array(nodes)) : (fieldId, nodes.first ?? .null)
    }

    /// Plain-text description, wrapped as a minimal ADF doc.
    public static func description(plainText text: String) -> (String, AnyJSON) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return ("description", .null) }
        // Split on blank lines so paragraphs survive.
        let paragraphs = text.split(separator: "\n\n", omittingEmptySubsequences: false)
        let paragraphNodes: [AnyJSON] = paragraphs.map { paragraph in
            .object([
                "type": .string("paragraph"),
                "content": .array([
                    .object([
                        "type": .string("text"),
                        "text": .string(String(paragraph))
                    ])
                ])
            ])
        }
        let doc: AnyJSON = .object([
            "type": .string("doc"),
            "version": .int(1),
            "content": .array(paragraphNodes)
        ])
        return ("description", doc)
    }

    public static func summary(_ value: String) -> (String, AnyJSON) {
        ("summary", .string(value))
    }

    public static func projectByKey(_ key: String) -> (String, AnyJSON) {
        ("project", .object(["key": .string(key)]))
    }

    public static func issueType(id: String) -> (String, AnyJSON) {
        ("issuetype", .object(["id": .string(id)]))
    }

    public static func assignee(accountID: String?) -> (String, AnyJSON) {
        ("assignee", accountID.map { .object(["accountId": .string($0)]) } ?? .null)
    }
}
