import Foundation

/// Evaluates a structured filter against an issue on the client, using the
/// same value conventions the filter builder stores: raw status names,
/// assignee and reporter display names, version names, `yyyy-MM-dd` dates,
/// and the `UNASSIGNED` / `NO_RELEASE` sentinels. Raw JQL cannot be evaluated
/// locally and reports `nil`.
public enum FilterMatcher {
    /// Whether `issue` satisfies `definition`, or nil when that cannot be
    /// decided locally (a non-empty raw JQL fragment).
    public static func matches(_ issue: JiraIssue, _ definition: FilterDefinition) -> Bool? {
        switch definition {
        case .jql(let raw):
            return raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? true : nil
        case .structured(let group):
            return matches(issue, group: group)
        }
    }

    /// AND binds tighter than OR, as in JQL: `A AND B OR C` is `(A AND B) OR C`.
    public static func matches(_ issue: JiraIssue, group: FilterGroup) -> Bool {
        guard !group.rows.isEmpty else { return true }
        var runs: [[Bool]] = [[]]
        for (index, row) in group.rows.enumerated() {
            if index > 0 && row.connector == .or { runs.append([]) }
            runs[runs.count - 1].append(matches(issue, node: row.node))
        }
        return runs.contains { $0.allSatisfy { $0 } }
    }

    public static func matches(_ issue: JiraIssue, condition: FilterCondition) -> Bool {
        if condition.field == .dueDate {
            return matchesDate(issue.dueDate, condition)
        }
        let actual = values(of: condition.field, on: issue)
        switch condition.op {
        case .isEmpty: return actual.isEmpty
        case .isNotEmpty: return !actual.isEmpty
        case .isAnyOf: return anyMatch(actual, condition)
        case .isNoneOf: return !anyMatch(actual, condition)
        case .on, .before, .after: return false
        }
    }

    /// The top-level conditions `issue` fails. Only meaningful when the root is
    /// a plain AND list; with OR joins or nested groups the whole filter is the
    /// reason, and this returns an empty list.
    public static func failingConditions(_ issue: JiraIssue, in definition: FilterDefinition) -> [FilterCondition] {
        guard case .structured(let group) = definition else { return [] }
        let plainAndList = group.rows.dropFirst().allSatisfy { $0.connector == .and }
        guard plainAndList else { return [] }
        return group.rows.compactMap { row in
            if case .condition(let condition) = row.node, !matches(issue, condition: condition) {
                return condition
            }
            return nil
        }
    }

    // MARK: - Internals

    private static func matches(_ issue: JiraIssue, node: FilterNode) -> Bool {
        switch node {
        case .condition(let condition): return matches(issue, condition: condition)
        case .group(let group): return matches(issue, group: group)
        }
    }

    static func values(of field: FilterField, on issue: JiraIssue) -> [String] {
        switch field {
        case .status: return [issue.status.name]
        case .priority: return issue.priority.name.isEmpty ? [] : [issue.priority.name]
        case .assignee: return issue.assignee.map { [$0.displayName] } ?? []
        case .reporter: return issue.reporter.map { [$0.displayName] } ?? []
        case .issueType: return [issue.issueType.name]
        case .labels: return issue.labels
        case .components: return issue.components.map(\.name)
        case .release: return issue.fixVersions.map(\.name)
        case .instanceName: return issue.instanceName.map { [$0] } ?? []
        case .dueDate: return issue.dueDate.map { [$0] } ?? []
        }
    }

    private static func anyMatch(_ actual: [String], _ condition: FilterCondition) -> Bool {
        for value in condition.values {
            if condition.field == .assignee, value == FilterOptions.unassignedSentinel {
                if actual.isEmpty { return true }
                continue
            }
            if condition.field == .release,
               value == JiraVersion.noReleaseSentinel || value.lowercased() == "no release" {
                if actual.isEmpty { return true }
                continue
            }
            if actual.contains(where: { equal($0, value) }) { return true }
            if condition.field == .status,
               actual.contains(where: { equal(StatusNormaliser.normalise($0), StatusNormaliser.normalise(value)) }) {
                return true
            }
        }
        return false
    }

    private static func equal(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    /// ISO `yyyy-MM-dd` strings compare correctly as plain strings.
    private static func matchesDate(_ raw: String?, _ condition: FilterCondition) -> Bool {
        switch condition.op {
        case .isEmpty: return raw == nil
        case .isNotEmpty: return raw != nil
        case .on:
            guard let raw, let value = condition.values.first else { return false }
            return raw == value
        case .before:
            guard let raw, let value = condition.values.first else { return false }
            return raw < value
        case .after:
            guard let raw, let value = condition.values.first else { return false }
            return raw > value
        case .isAnyOf:
            guard let raw else { return false }
            return condition.values.contains(raw)
        case .isNoneOf:
            guard let raw else { return true }
            return !condition.values.contains(raw)
        }
    }
}
