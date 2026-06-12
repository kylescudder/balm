import Foundation
import BalmModels

/// Mirror of the raw Jira REST issue payload, just enough for our needs.
/// Mapped to the domain `JiraIssue` via `JiraIssueMapper`.
public struct RawJiraIssue: Decodable, Sendable {
    public let id: String
    public let key: String
    public let fields: Fields

    /// Sprints found by scanning every `customfield_*` for sprint-shaped values.
    /// Tenant-agnostic — the Sprint custom field id differs per Jira site.
    public let sprintCandidates: [JiraSprint]

    enum CodingKeys: String, CodingKey {
        case id, key, fields, changelog
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.key = try c.decode(String.self, forKey: .key)
        self.fields = try c.decode(Fields.self, forKey: .fields)
        self.changelog = try c.decodeIfPresent(RawJiraChangelogPage.self, forKey: .changelog)
        // Re-read the fields object generically to locate the sprint custom field.
        let rawFields = (try? c.decode([String: AnyJSON].self, forKey: .fields)) ?? [:]
        self.sprintCandidates = RawJiraIssue.scanSprints(in: rawFields)
    }

    /// Scans all `customfield_*` entries for an array of sprint values (objects
    /// with `name` + `state`, or legacy greenhopper strings). Keys are sorted so
    /// selection is deterministic when more than one field qualifies.
    static func scanSprints(in fields: [String: AnyJSON]) -> [JiraSprint] {
        for key in fields.keys.sorted() where key.hasPrefix("customfield_") {
            guard case .array(let elements)? = fields[key], !elements.isEmpty else { continue }
            let sprints = elements.compactMap(sprint(from:))
            if !sprints.isEmpty { return sprints }
        }
        return []
    }

    private static func sprint(from json: AnyJSON) -> JiraSprint? {
        switch json {
        case .string(let s):
            return JiraSprint.parse(legacy: s)
        case .object(let o):
            guard case .string(let name)? = o["name"], !name.isEmpty,
                  case .string(let state)? = o["state"] else { return nil }
            let id: String
            switch o["id"] {
            case .int(let i)?: id = String(i)
            case .double(let d)?: id = String(Int(d))
            case .string(let s)?: id = s
            default: id = name
            }
            return JiraSprint(id: id, name: name, state: state)
        default:
            return nil
        }
    }

    public struct Fields: Decodable, Sendable {
        public let summary: String
        public let status: JiraStatus
        public let priority: JiraPriority?
        public let assignee: JiraUserSummary?
        public let reporter: JiraUserSummary?
        public let issuetype: JiraIssueType
        public let created: Date?
        public let updated: Date?
        public let duedate: String?
        public let labels: [String]?
        public let components: [JiraComponent]?
        public let fixVersions: [JiraVersion]?
        public let description: ADFEnvelope?
        public let sprint: JiraSprint?
        public let sprints: [JiraSprint]?
        public let closedSprints: [JiraSprint]?
        public let customfield_10312: FlexibleComponentField?
        public let customfield_10020: SprintsCustomField?
        public let comment: RawJiraCommentsPage?
        public let attachment: [RawJiraAttachment]?
        public let issuelinks: [RawJiraIssueLink]?

        enum CodingKeys: String, CodingKey {
            case summary, status, priority, assignee, reporter, issuetype
            case created, updated, duedate, labels, components, fixVersions
            case description, sprint, sprints, closedSprints
            case customfield_10312, customfield_10020
            case comment, attachment, issuelinks
        }
    }

    /// Returned only when `expand=changelog` is set on the issue request.
    public let changelog: RawJiraChangelogPage?
}

/// Wrapper that can hold either a JSON object (ADF) or `null`. Stored as raw
/// `Data` so downstream `BalmADF` can parse it lazily.
public struct ADFEnvelope: Decodable, Sendable {
    public let rawJSON: Data

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.rawJSON = Data()
            return
        }
        // Re-encode whatever was there back to Data — the underlying ADF tree
        // is parsed by the ADF module, not here.
        let anyValue = try container.decode(AnyJSON.self)
        self.rawJSON = try JSONEncoder().encode(anyValue)
    }
}

/// Atlassian returns `customfield_10312` (a custom components field) in either
/// of three shapes depending on field config: array of component objects, a
/// single component object, or null. Tolerate all three.
public enum FlexibleComponentField: Decodable, Sendable {
    case array([JiraComponent])
    case single(JiraComponent)
    case none

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .none; return }
        if let arr = try? container.decode([JiraComponent].self) {
            self = .array(arr)
            return
        }
        if let one = try? container.decode(JiraComponent.self) {
            self = .single(one)
            return
        }
        self = .none
    }

    public var components: [JiraComponent] {
        switch self {
        case .array(let a): return a
        case .single(let c): return [c]
        case .none: return []
        }
    }
}

/// Atlassian sometimes returns `customfield_10020` as an array of sprint objects
/// (sometimes a stringified array). Tolerate both shapes.
public enum SprintsCustomField: Decodable, Sendable {
    case structured([JiraSprint])
    case strings([String])

    public init(from decoder: Decoder) throws {
        if let arr = try? decoder.singleValueContainer().decode([JiraSprint].self) {
            self = .structured(arr)
            return
        }
        if let arr = try? decoder.singleValueContainer().decode([String].self) {
            self = .strings(arr)
            return
        }
        self = .strings([])
    }
}

/// Minimal AnyJSON used to round-trip arbitrary JSON values for ADF storage.
public indirect enum AnyJSON: Codable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([AnyJSON])
    case object([String: AnyJSON])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let i = try? c.decode(Int.self) { self = .int(i); return }
        if let d = try? c.decode(Double.self) { self = .double(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([AnyJSON].self) { self = .array(a); return }
        if let o = try? c.decode([String: AnyJSON].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON")
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .int(let i): try c.encode(i)
        case .double(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}
