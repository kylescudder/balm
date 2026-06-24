import Foundation
import BalmModels

/// Compiles a JQL string from a project key, the selected sprints, and a
/// `FilterDefinition` (a structured condition tree or a raw-JQL fragment).
///
/// The output is always scoped as `project = X AND <sprint clause> AND <fragment>`,
/// preserving the historic web behaviour: returns `nil` when no sprint is
/// selected (no results in that case). For the simple all-AND structured case
/// the output is byte-identical to the previous flat builder.
public struct JQLBuilder: Sendable, Equatable {
    public let projectKey: String
    public let sprints: [String]
    public let definition: FilterDefinition
    /// The JQL field name to use for `FilterField.components`. Defaults to the
    /// standard `component`, but a tenant whose components live in a custom
    /// select field passes e.g. `cf[10312]` (resolved from create-metadata).
    public let componentField: String
    public let orderByCreated: Bool
    public let instanceFieldID: String?

    public init(
        projectKey: String,
        sprints: [String],
        definition: FilterDefinition = .empty,
        componentField: String = "component",
        orderByCreated: Bool = true,
        instanceFieldID: String? = nil
    ) {
        self.projectKey = projectKey
        self.sprints = sprints
        self.definition = definition
        self.componentField = componentField
        self.orderByCreated = orderByCreated
        self.instanceFieldID = instanceFieldID
    }

    public func build() -> String? {
        guard !sprints.isEmpty else { return nil }

        var clauses: [String] = ["project = \(projectKey)"]

        // Sprint — mandatory; respects backlog/NO_SPRINT sentinel.
        let (sprintClause, addOrder) = sprintClauses()
        clauses.append(sprintClause)

        var userOrderBy: String? = nil

        switch definition {
        case .structured(let group):
            if let fragment = compile(group, topLevel: true) {
                clauses.append(fragment)
            }
        case .jql(let raw):
            let (whereExpr, order) = splitOrderBy(raw)
            userOrderBy = order
            if let w = whereExpr {
                clauses.append("(\(w))")
            }
        }
        var jql = clauses.joined(separator: " AND ")
        if let order = userOrderBy {
            jql += " order by \(order)"
        } else if orderByCreated && addOrder {
            jql += " order by created"
        }
        return jql
    }

    /// The discretionary JQL fragment for this builder's `definition`, without
    /// project/sprint scoping. Used by the UI to prefill the "Advanced (JQL)"
    /// editor from a structured tree. `nil` when the definition is empty.
    public func discretionaryFragment() -> String? {
        switch definition {
        case .structured(let group):
            return compile(group, topLevel: true)
        case .jql(let raw):
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    // MARK: - Structured compilation

    /// Compile a group to a JQL fragment, or `nil` if it has no usable rows.
    ///
    /// Rows are joined by their per-row connectors. The rows are split into
    /// AND-runs (a new run starts at each `OR` connector) and the runs are
    /// OR-joined; JQL's own precedence (AND binds tighter than OR) then yields
    /// the intended grouping, e.g. `A AND B OR C` == `(A AND B) OR C`.
    ///
    /// A top-level all-AND fragment is left unwrapped so it merges with the
    /// AND-ed project/sprint clauses (and stays byte-identical to the old
    /// builder); a top-level fragment containing OR is parenthesised. A nested
    /// fragment is parenthesised whenever it is compound, so it embeds safely.
    private func compile(_ group: FilterGroup, topLevel: Bool) -> String? {
        var kept: [(connector: FilterConnector, text: String)] = []
        for row in group.rows {
            guard let text = compileOperand(row.node) else { continue }
            kept.append((row.connector, text))
        }
        guard let first = kept.first else { return nil }

        var runs: [[String]] = [[first.text]]
        for item in kept.dropFirst() {
            if item.connector == .and {
                runs[runs.count - 1].append(item.text)
            } else {
                runs.append([item.text])
            }
        }
        let expr = runs.map { $0.joined(separator: " AND ") }.joined(separator: " OR ")

        if topLevel {
            return runs.count > 1 ? "(\(expr))" : expr
        }
        return kept.count > 1 ? "(\(expr))" : expr
    }

    /// Compile a node to an operand safe to embed in any AND/OR context — a
    /// condition clause, or a nested group already parenthesised when compound.
    private func compileOperand(_ node: FilterNode) -> String? {
        switch node {
        case .group(let g): return compile(g, topLevel: false)
        case .condition(let c): return compile(c)
        }
    }

    private func compile(_ condition: FilterCondition) -> String? {
        let field: String
        if condition.field == .components {
            field = componentField
        } else if condition.field == .instanceName, let id = instanceFieldID {
            let numericID = id.replacingOccurrences(of: "customfield_", with: "")
            field = "cf[\(numericID)]"
        } else if condition.field == .instanceName {
            return nil
        } else {
            field = condition.field.jqlField
        }
        switch condition.op {
        case .isEmpty:
            return "\(field) is EMPTY"
        case .isNotEmpty:
            return "\(field) is not EMPTY"
        case .on, .before, .after:
            guard let value = condition.values.first, !value.isEmpty else { return nil }
            let cmp = condition.op == .before ? "<=" : (condition.op == .after ? ">=" : "=")
            return "\(field) \(cmp) \"\(escape(value))\""
        case .isAnyOf, .isNoneOf:
            let values = condition.values.filter { !$0.isEmpty }
            guard !values.isEmpty else { return nil }
            let negate = condition.op == .isNoneOf
            if isSentinelField(condition.field) {
                // assignee / fixVersion: expand the EMPTY sentinel and OR (or, for
                // "none of", AND-of-negations) the equalities — ports the old
                // assigneeClause()/releaseClause() so output is unchanged.
                let parts = values.map { sentinelOrEquality(condition.field, $0, negate: negate) }
                let sep = negate ? " AND " : " OR "
                return "(\(parts.joined(separator: sep)))"
            } else {
                let keyword = negate ? "NOT IN" : "IN"
                return "\(field) \(keyword) (\(quoted(values)))"
            }
        }
    }

    // MARK: - Sprint

    private func sprintClauses() -> (clause: String, addOrder: Bool) {
        let hasBacklog = sprints.contains { isBacklog($0) }
        let named = sprints.filter { !isBacklog($0) }

        if hasBacklog && !named.isEmpty {
            return ("(sprint is EMPTY OR sprint IN (\(quoted(named))))", false)
        } else if hasBacklog {
            return ("sprint is EMPTY", false)
        } else {
            return ("sprint IN (\(quoted(named)))", true)
        }
    }

    // MARK: - Raw JQL

    /// Split a raw JQL fragment into its where-part and an optional trailing
    /// `order by`. The order clause can't live inside the parentheses we wrap
    /// the where-part in, so it's lifted out and re-appended at the very end.
    private func splitOrderBy(_ raw: String) -> (whereExpr: String?, order: String?) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (nil, nil) }
        if let r = trimmed.range(of: "order by", options: [.caseInsensitive, .backwards]) {
            let whereExpr = String(trimmed[..<r.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let order = String(trimmed[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return (whereExpr.isEmpty ? nil : whereExpr, order.isEmpty ? nil : order)
        }
        return (trimmed, nil)
    }

    // MARK: - Helpers

    private func isSentinelField(_ field: FilterField) -> Bool {
        field == .assignee || field == .release
    }

    private func isSentinelValue(_ field: FilterField, _ value: String) -> Bool {
        switch field {
        case .assignee:
            return value == FilterOptions.unassignedSentinel
        case .release:
            return value == JiraVersion.noReleaseSentinel || value.lowercased() == "no release"
        default:
            return false
        }
    }

    private func sentinelOrEquality(_ field: FilterField, _ value: String, negate: Bool) -> String {
        let jqlField = field.jqlField
        if isSentinelValue(field, value) {
            return negate ? "\(jqlField) is not EMPTY" : "\(jqlField) is EMPTY"
        }
        return negate ? "\(jqlField) != \"\(escape(value))\"" : "\(jqlField) = \"\(escape(value))\""
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
