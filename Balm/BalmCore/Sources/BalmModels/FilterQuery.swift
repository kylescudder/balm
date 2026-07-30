import Foundation

/// A field that can be filtered on in the structured condition builder. Each
/// case knows its human label, its JQL field name, and whether it takes
/// enumerated values or a date — which in turn gates the available operators.
public enum FilterField: String, Codable, Sendable, CaseIterable, Identifiable {
    case status
    case priority
    case assignee
    case reporter
    case issueType
    case labels
    case components
    case release
    case dueDate
    case instanceName

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .status: return "Status"
        case .priority: return "Priority"
        case .assignee: return "Assignee"
        case .reporter: return "Reporter"
        case .issueType: return "Type"
        case .labels: return "Labels"
        case .components: return "Components"
        case .release: return "Release"
        case .dueDate: return "Due Date"
        case .instanceName: return "Instance"
        }
    }

    /// The JQL field name. Mirrors `JQLBuilder`'s historic mappings exactly so
    /// the compiled output is unchanged for the simple AND case.
    /// For `.instanceName` the actual field name is dynamic (`cf[N]`); the
    /// builder substitutes it when the tenant's field id is known.
    public var jqlField: String {
        switch self {
        case .status: return "status"
        case .priority: return "priority"
        case .assignee: return "assignee"
        case .reporter: return "reporter"
        case .issueType: return "issuetype"
        case .labels: return "labels"
        case .components: return "component"
        case .release: return "fixVersion"
        case .dueDate: return "duedate"
        case .instanceName: return "cf[INSTANCE]"
        }
    }

    public enum Kind: Sendable { case enumerated, date }

    public var kind: Kind { self == .dueDate ? .date : .enumerated }
}

/// The comparison applied to a field. Which operators are valid depends on the
/// field's `Kind` (see `validOperators(for:)`).
public enum FilterOperator: String, Codable, Sendable, CaseIterable, Identifiable {
    case isAnyOf
    case isNoneOf
    case isEmpty
    case isNotEmpty
    case before
    case after
    case on

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .isAnyOf: return "is any of"
        case .isNoneOf: return "is none of"
        case .isEmpty: return "is empty"
        case .isNotEmpty: return "is not empty"
        case .before: return "before"
        case .after: return "after"
        case .on: return "on"
        }
    }

    /// Whether the operator needs accompanying value(s). `isEmpty`/`isNotEmpty`
    /// stand alone.
    public var needsValues: Bool {
        switch self {
        case .isEmpty, .isNotEmpty: return false
        default: return true
        }
    }

    public static func validOperators(for field: FilterField) -> [FilterOperator] {
        switch field.kind {
        case .enumerated: return [.isAnyOf, .isNoneOf, .isEmpty, .isNotEmpty]
        case .date: return [.on, .before, .after, .isEmpty, .isNotEmpty]
        }
    }
}

/// A single leaf condition: a field, an operator, and the value(s) it applies
/// to. `values` is empty for `isEmpty`/`isNotEmpty`; a single ISO `yyyy-MM-dd`
/// string for date operators.
public struct FilterCondition: Identifiable, Codable, Sendable, Hashable {
    public var id: UUID
    public var field: FilterField
    public var op: FilterOperator
    public var values: [String]

    public init(
        id: UUID = UUID(),
        field: FilterField,
        op: FilterOperator,
        values: [String] = []
    ) {
        self.id = id
        self.field = field
        self.op = op
        self.values = values
    }
}

/// The boolean joiner between two adjacent rows. `and` binds tighter than `or`
/// (standard JQL precedence), so `A AND B OR C` means `(A AND B) OR C`. Explicit
/// nested groups override that precedence.
public enum FilterConnector: String, Codable, Sendable, CaseIterable, Identifiable {
    case and
    case or

    public var id: String { rawValue }
    public var label: String { self == .and ? "AND" : "OR" }
}

/// A node in the filter tree — either a leaf condition or a nested group.
/// `indirect` lets a group contain further groups.
public indirect enum FilterNode: Codable, Sendable, Hashable, Identifiable {
    case condition(FilterCondition)
    case group(FilterGroup)

    public var id: UUID {
        switch self {
        case .condition(let c): return c.id
        case .group(let g): return g.id
        }
    }
}

/// One row in a group: a node plus the connector joining it to the *previous*
/// row. The first row's connector is ignored (nothing precedes it).
public struct FilterRow: Identifiable, Codable, Sendable, Hashable {
    public var id: UUID
    public var connector: FilterConnector
    public var node: FilterNode

    public init(id: UUID = UUID(), connector: FilterConnector = .and, node: FilterNode) {
        self.id = id
        self.connector = connector
        self.node = node
    }
}

/// An ordered list of rows joined by their per-row connectors. The root of a
/// structured filter is a `FilterGroup`; nested groups set precedence.
public struct FilterGroup: Identifiable, Codable, Sendable, Hashable {
    public var id: UUID
    public var rows: [FilterRow]

    public init(id: UUID = UUID(), rows: [FilterRow] = []) {
        self.id = id
        self.rows = rows
    }

    public var isEmpty: Bool { rows.isEmpty }
}

/// The discretionary filter the user edits: either a structured group tree or a
/// raw JQL fragment (the "Advanced" escape hatch). Project + sprint scoping is
/// applied around it by `JQLBuilder`.
public enum FilterDefinition: Codable, Sendable, Hashable {
    case structured(FilterGroup)
    case jql(String)

    public static let empty = FilterDefinition.structured(FilterGroup(rows: []))

    public var isEmpty: Bool {
        switch self {
        case .structured(let g): return g.isEmpty
        case .jql(let s): return s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Number of active filters for the toolbar badge: top-level row count for a
    /// structured tree, or 1 for any non-empty raw JQL.
    public var activeCount: Int {
        switch self {
        case .structured(let g): return g.rows.count
        case .jql(let s): return s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1
        }
    }
}

// MARK: - Legacy migration

public extension FilterOptions {
    /// Convert the legacy flat filter into an `.all` group of conditions.
    /// Section order mirrors the old `JQLBuilder.build()` so the compiled JQL is
    /// byte-identical after migration. `UNASSIGNED` / `NO_RELEASE` sentinel
    /// values are preserved verbatim — the compiler still expands them. Reporter
    /// (previously dropped from JQL) is now included and so becomes effective.
    var asFilterGroup: FilterGroup {
        var rows: [FilterRow] = []
        func add(_ node: FilterNode) {
            rows.append(FilterRow(connector: .and, node: node))
        }
        func add(_ field: FilterField, _ values: [String]) {
            guard !values.isEmpty else { return }
            add(.condition(FilterCondition(field: field, op: .isAnyOf, values: values)))
        }
        add(.status, status)
        add(.priority, priority)
        add(.assignee, assignee)
        add(.issueType, issueType)
        if let from = dueDateFrom, !from.isEmpty {
            add(.condition(FilterCondition(field: .dueDate, op: .after, values: [from])))
        }
        if let to = dueDateTo, !to.isEmpty {
            add(.condition(FilterCondition(field: .dueDate, op: .before, values: [to])))
        }
        add(.labels, labels)
        add(.components, components)
        add(.release, release)
        add(.reporter, reporter)
        add(.instanceName, instanceName)
        return FilterGroup(rows: rows)
    }

    var asFilterDefinition: FilterDefinition { .structured(asFilterGroup) }
}
