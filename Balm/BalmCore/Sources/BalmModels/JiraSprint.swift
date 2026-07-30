import Foundation

public struct JiraSprint: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var state: String
    public var startDate: Date?
    public var endDate: Date?
    public var completeDate: Date?

    public init(
        id: String,
        name: String,
        state: String,
        startDate: Date? = nil,
        endDate: Date? = nil,
        completeDate: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.state = state
        self.startDate = startDate
        self.endDate = endDate
        self.completeDate = completeDate
    }

    enum CodingKeys: String, CodingKey {
        case id, name, state, startDate, endDate, completeDate
    }

    /// Tolerant decoder. Jira returns sprint `id` as an **integer** (both the
    /// agile `/board/{id}/sprint` listing and the `customfield_10020` array),
    /// so a plain `String` decode throws and silently wipes every sprint. We
    /// also accept the legacy greenhopper string form
    /// (`...Sprint@x[id=12,name=Cycle 9,state=ACTIVE,...]`).
    public init(from decoder: Decoder) throws {
        // Legacy stringified sprint.
        if let single = try? decoder.singleValueContainer(),
           let raw = try? single.decode(String.self) {
            let parsed = JiraSprint.parse(legacy: raw) ?? JiraSprint(id: raw, name: raw, state: "")
            self = parsed
            return
        }

        let c = try decoder.container(keyedBy: CodingKeys.self)

        if let s = try? c.decode(String.self, forKey: .id) {
            self.id = s
        } else if let i = try? c.decode(Int.self, forKey: .id) {
            self.id = String(i)
        } else if let d = try? c.decode(Double.self, forKey: .id) {
            self.id = String(Int(d))
        } else {
            self.id = ""
        }

        let decodedName = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? nil
        self.name = (decodedName?.isEmpty == false) ? decodedName! : id
        self.state = ((try? c.decodeIfPresent(String.self, forKey: .state)) ?? nil) ?? ""

        // Dates are non-critical — never let a format mismatch fail the issue.
        self.startDate = (try? c.decodeIfPresent(Date.self, forKey: .startDate)) ?? nil
        self.endDate = (try? c.decodeIfPresent(Date.self, forKey: .endDate)) ?? nil
        self.completeDate = (try? c.decodeIfPresent(Date.self, forKey: .completeDate)) ?? nil
    }

    /// Parses the legacy greenhopper sprint string. Mirrors the web's
    /// `extractSprintFromFields` regex handling (`lib/jira-api.ts:319-340`).
    public static func parse(legacy raw: String) -> JiraSprint? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        func field(_ key: String) -> String? {
            guard let r = trimmed.range(of: "\(key)=") else { return nil }
            let rest = trimmed[r.upperBound...]
            let end = rest.firstIndex(where: { $0 == "," || $0 == "]" }) ?? rest.endIndex
            let value = rest[rest.startIndex..<end].trimmingCharacters(in: .whitespaces)
            return value.isEmpty || value == "<null>" ? nil : value
        }

        let id = field("id")
        let name = field("name")
        let state = field("state")
        let resolvedName = name ?? id ?? trimmed
        guard id != nil || !resolvedName.isEmpty else { return nil }
        return JiraSprint(id: id ?? resolvedName, name: resolvedName, state: state ?? "")
    }
}

public extension JiraSprint {
    static let backlogSentinel = "NO_SPRINT"
    static let backlog = JiraSprint(id: backlogSentinel, name: "Backlog", state: "")

    /// The issue's "current" sprint from a list that may span its whole sprint
    /// history: prefer the active sprint, then a future sprint, else the most
    /// recent entry.
    static func current(from sprints: [JiraSprint]) -> JiraSprint? {
        guard !sprints.isEmpty else { return nil }
        if let active = sprints.last(where: { $0.state.lowercased() == "active" }) { return active }
        if let future = sprints.last(where: { $0.state.lowercased() == "future" }) { return future }
        return sprints.last
    }
}
