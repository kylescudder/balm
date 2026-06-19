import SwiftUI
import BalmModels

/// Linear-style recursive condition builder. Renders a `FilterGroup` as a
/// "Match All / Any of the following" block with a row per child condition and
/// indented sub-blocks per nested group. Edits the bound group in place.
struct FilterBuilderView: View {
    @Binding var group: FilterGroup
    let options: AvailableFilterOptions
    var isRoot: Bool = true
    var onRemove: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            ForEach($group.children) { $node in
                FilterNodeRow(node: $node, options: options, onRemove: remover(for: $node.wrappedValue.id))
            }
            if group.children.isEmpty {
                Text("No conditions yet — add one below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            addButtons
        }
        .padding(isRoot ? 0 : 12)
        .background {
            if !isRoot {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.08))
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Match")
            Picker("Combinator", selection: $group.combinator) {
                Text("All").tag(Combinator.all)
                Text("Any").tag(Combinator.any)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Text("of the following")
                .foregroundStyle(.secondary)
            Spacer()
            if let onRemove {
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash").imageScale(.small)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Remove group")
            }
        }
        .font(.callout)
    }

    private var addButtons: some View {
        HStack(spacing: 14) {
            Button { addCondition() } label: { Label("Add condition", systemImage: "plus.circle") }
            Button { addGroup() } label: { Label("Add group", systemImage: "plus.square.on.square") }
        }
        .buttonStyle(.borderless)
        .font(.callout)
    }

    private func remover(for id: UUID) -> () -> Void {
        { group.children.removeAll { $0.id == id } }
    }

    private func addCondition() {
        let used = Set(group.children.compactMap { node -> FilterField? in
            if case .condition(let c) = node { return c.field }
            return nil
        })
        let field = FilterField.allCases.first { !used.contains($0) } ?? .status
        group.children.append(.condition(FilterCondition(field: field, op: .isAnyOf)))
    }

    private func addGroup() {
        group.children.append(.group(FilterGroup(combinator: .any, children: [])))
    }
}

/// Dispatches a node binding to either a condition row or a nested builder.
private struct FilterNodeRow: View {
    @Binding var node: FilterNode
    let options: AvailableFilterOptions
    let onRemove: () -> Void

    var body: some View {
        if let condition = $node.asCondition {
            ConditionRow(condition: condition, options: options, onRemove: onRemove)
        } else if let group = $node.asGroup {
            FilterBuilderView(group: group, options: options, isRoot: false, onRemove: onRemove)
        }
    }
}

/// A single field/operator/value row.
private struct ConditionRow: View {
    @Binding var condition: FilterCondition
    let options: AvailableFilterOptions
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Menu(condition.field.displayName) {
                ForEach(FilterField.allCases) { field in
                    Button(field.displayName) { selectField(field) }
                }
            }
            .fixedSize()

            Menu(condition.op.displayName) {
                ForEach(FilterOperator.validOperators(for: condition.field)) { op in
                    Button(op.displayName) { selectOperator(op) }
                }
            }
            .fixedSize()

            valueControl

            Spacer(minLength: 0)

            Button(role: .destructive, action: onRemove) {
                Image(systemName: "minus.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Remove condition")
        }
    }

    @ViewBuilder private var valueControl: some View {
        if condition.op.needsValues {
            if condition.field.kind == .date {
                DateConditionControl(values: $condition.values)
            } else {
                KeyboardMultiSelect(
                    title: condition.field.displayName,
                    options: Self.multiSelectOptions(for: condition.field, from: options),
                    selection: $condition.values
                )
            }
        }
    }

    private func selectField(_ field: FilterField) {
        guard field != condition.field else { return }
        let kindChanged = field.kind != condition.field.kind
        condition.field = field
        if !FilterOperator.validOperators(for: field).contains(condition.op) {
            condition.op = FilterOperator.validOperators(for: field).first ?? .isAnyOf
        }
        if kindChanged { condition.values = [] }
    }

    private func selectOperator(_ op: FilterOperator) {
        condition.op = op
        if !op.needsValues { condition.values = [] }
    }

    /// Map a field to its selectable value pool, reusing the same derivation the
    /// old sectioned sheet used (status labels normalised; named options for
    /// assignee/reporter/release).
    static func multiSelectOptions(for field: FilterField, from options: AvailableFilterOptions) -> [MultiSelectOption] {
        switch field {
        case .status:
            return options.statuses
                .map { MultiSelectOption(id: $0, label: StatusNormaliser.normalise($0)) }
                .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
        case .priority:
            return options.priorities.map { MultiSelectOption(id: $0, label: $0) }
        case .issueType:
            return options.issueTypes.map { MultiSelectOption(id: $0, label: $0) }
        case .labels:
            return options.labels.map { MultiSelectOption(id: $0, label: $0) }
        case .components:
            return options.components.map { MultiSelectOption(id: $0, label: $0) }
        case .assignee:
            return options.assignees.map { MultiSelectOption(id: $0.id, label: $0.displayName) }
        case .reporter:
            return options.reporters.map { MultiSelectOption(id: $0.id, label: $0.displayName) }
        case .release:
            return options.releases.map { MultiSelectOption(id: $0.id, label: $0.displayName) }
        case .dueDate:
            return []
        }
    }
}

/// Single-date editor for date conditions. Stores the date as one ISO
/// `yyyy-MM-dd` element in `values`.
private struct DateConditionControl: View {
    @Binding var values: [String]
    @State private var date: Date

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init(values: Binding<[String]>) {
        self._values = values
        if let raw = values.wrappedValue.first, let parsed = Self.formatter.date(from: raw) {
            _date = State(initialValue: parsed)
        } else {
            _date = State(initialValue: Date())
        }
    }

    var body: some View {
        DatePicker("Date", selection: $date, displayedComponents: .date)
            .labelsHidden()
            .onChange(of: date) { _, newValue in
                values = [Self.formatter.string(from: newValue)]
            }
            .onAppear {
                if values.isEmpty { values = [Self.formatter.string(from: date)] }
            }
    }
}

// MARK: - Node binding helpers

extension Binding where Value == FilterNode {
    /// A binding to the wrapped condition, or `nil` if the node is a group.
    var asCondition: Binding<FilterCondition>? {
        guard case .condition = wrappedValue else { return nil }
        return Binding<FilterCondition>(
            get: {
                if case .condition(let c) = wrappedValue { return c }
                return FilterCondition(field: .status, op: .isAnyOf)
            },
            set: { wrappedValue = .condition($0) }
        )
    }

    /// A binding to the wrapped group, or `nil` if the node is a condition.
    var asGroup: Binding<FilterGroup>? {
        guard case .group = wrappedValue else { return nil }
        return Binding<FilterGroup>(
            get: {
                if case .group(let g) = wrappedValue { return g }
                return FilterGroup()
            },
            set: { wrappedValue = .group($0) }
        )
    }
}
