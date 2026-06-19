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
        }
    }

    /// The JQL field name. Mirrors `JQLBuilder`'s historic mappings exactly so
    /// the compiled output is unchanged for the simple AND case.
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

/// How a group's children combine: `all` → AND, `any` → OR.
public enum Combinator: String, Codable, Sendable, CaseIterable, Identifiable {
    case all
    case any

    public var id: String { rawValue }
    public var displayName: String { self == .all ? "All" : "Any" }
    public var jqlSeparator: String { self == .all ? " AND " : " OR " }
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

/// A combinator plus an ordered list of child nodes. The root of a structured
/// filter is a `FilterGroup`.
public struct FilterGroup: Identifiable, Codable, Sendable, Hashable {
    public var id: UUID
    public var combinator: Combinator
    public var children: [FilterNode]

    public init(
        id: UUID = UUID(),
        combinator: Combinator = .all,
        children: [FilterNode] = []
    ) {
        self.id = id
        self.combinator = combinator
        self.children = children
    }

    public var isEmpty: Bool { children.isEmpty }
}

/// The discretionary filter the user edits: either a structured group tree or a
/// raw JQL fragment (the "Advanced" escape hatch). Project + sprint scoping is
/// applied around it by `JQLBuilder`.
public enum FilterDefinition: Codable, Sendable, Hashable {
    case structured(FilterGroup)
    case jql(String)

    public static let empty = FilterDefinition.structured(FilterGroup(combinator: .all, children: []))

    public var isEmpty: Bool {
        switch self {
        case .structured(let g): return g.isEmpty
        case .jql(let s): return s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Number of active filters for the toolbar badge: top-level child count
    /// for a structured tree, or 1 for any non-empty raw JQL.
    public var activeCount: Int {
        switch self {
        case .structured(let g): return g.children.count
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
        var children: [FilterNode] = []
        func add(_ field: FilterField, _ values: [String]) {
            guard !values.isEmpty else { return }
            children.append(.condition(FilterCondition(field: field, op: .isAnyOf, values: values)))
        }
        add(.status, status)
        add(.priority, priority)
        add(.assignee, assignee)
        add(.issueType, issueType)
        if let from = dueDateFrom, !from.isEmpty {
            children.append(.condition(FilterCondition(field: .dueDate, op: .after, values: [from])))
        }
        if let to = dueDateTo, !to.isEmpty {
            children.append(.condition(FilterCondition(field: .dueDate, op: .before, values: [to])))
        }
        add(.labels, labels)
        add(.components, components)
        add(.release, release)
        add(.reporter, reporter)
        return FilterGroup(combinator: .all, children: children)
    }

    var asFilterDefinition: FilterDefinition { .structured(asFilterGroup) }
}
