import Foundation
import BalmModels

/// Direct port of `lib/jira-api.ts:1265-1360`.
/// Compiles a JQL string from a project key + `FilterOptions`.
/// Returns `nil` when the sprint filter is empty — mirrors the web behaviour
/// of returning no results in that case.
public struct JQLBuilder: Sendable, Equatable {
    public let projectKey: String
    public let filters: FilterOptions
    public let orderByCreated: Bool

    public init(projectKey: String, filters: FilterOptions, orderByCreated: Bool = true) {
        self.projectKey = projectKey
        self.filters = filters
        self.orderByCreated = orderByCreated
    }

    public func build() -> String? {
        guard !filters.sprint.isEmpty else { return nil }

        var clauses: [String] = ["project = \(projectKey)"]
        var appendOrder = false

        // Sprint — mandatory; respects backlog/NO_SPRINT sentinel.
        let (sprintClause, sprintOrder) = sprintClauses()
        clauses.append(sprintClause)
        appendOrder = sprintOrder

        if !filters.status.isEmpty {
            clauses.append("status IN (\(quoted(filters.status)))")
        }
        if !filters.priority.isEmpty {
            clauses.append("priority IN (\(quoted(filters.priority)))")
        }
        if let assigneeClause = assigneeClause() {
            clauses.append(assigneeClause)
        }
        if !filters.issueType.isEmpty {
            clauses.append("issuetype IN (\(quoted(filters.issueType)))")
        }
        if let from = filters.dueDateFrom, !from.isEmpty {
            clauses.append("duedate >= \"\(escape(from))\"")
        }
        if let to = filters.dueDateTo, !to.isEmpty {
            clauses.append("duedate <= \"\(escape(to))\"")
        }
        if !filters.labels.isEmpty {
            clauses.append("labels IN (\(quoted(filters.labels)))")
        }
        if !filters.components.isEmpty {
            clauses.append("component IN (\(quoted(filters.components)))")
        }
        if let releaseClause = releaseClause() {
            clauses.append(releaseClause)
        }

        var jql = clauses.joined(separator: " AND ")
        if orderByCreated && appendOrder {
            jql += " order by created"
        }
        return jql
    }

    // MARK: - Helpers

    private func sprintClauses() -> (clause: String, addOrder: Bool) {
        let hasBacklog = filters.sprint.contains { isBacklog($0) }
        let named = filters.sprint.filter { !isBacklog($0) }

        if hasBacklog && !named.isEmpty {
            return ("(sprint is EMPTY OR sprint IN (\(quoted(named))))", false)
        } else if hasBacklog {
            return ("sprint is EMPTY", false)
        } else {
            return ("sprint IN (\(quoted(named)))", true)
        }
    }

    private func assigneeClause() -> String? {
        guard !filters.assignee.isEmpty else { return nil }
        let conds: [String] = filters.assignee.map { value in
            if value == FilterOptions.unassignedSentinel {
                return "assignee is EMPTY"
            } else {
                return "assignee = \"\(escape(value))\""
            }
        }
        return "(\(conds.joined(separator: " OR ")))"
    }

    private func releaseClause() -> String? {
        guard !filters.release.isEmpty else { return nil }
        let conds: [String] = filters.release.map { value in
            if value == JiraVersion.noReleaseSentinel
                || value.lowercased() == "no release" {
                return "fixVersion is EMPTY"
            } else {
                return "fixVersion = \"\(escape(value))\""
            }
        }
        return "(\(conds.joined(separator: " OR ")))"
    }

    private func isBacklog(_ s: String) -> Bool {
        s.lowercased() == "backlog" || s == JiraSprint.backlogSentinel
    }

    private func quoted(_ values: [String]) -> String {
        values.map { "\"\(escape($0))\"" }.joined(separator: ",")
    }

    /// Escape double-quotes and backslashes — improves on the web which doesn't escape.
    private func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
