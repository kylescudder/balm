import SwiftUI
import BalmModels
import BalmDesignSystem

/// The row above the list or board that says what is in view: which sprints,
/// which filters (as removable chips), and how many issues that leaves. Sprint
/// opens with S, Filter with F. On iOS the view switcher lives here too.
struct ScopeBar: View {
    let model: IssueListViewModel
    @Bindable var filterStore: FilterStore
    @Binding var viewMode: IssueViewMode
    /// The signed-in user's display name, so "Assignee is <me>" reads as "me".
    let currentUserName: String?
    /// Replaces the issue count while a search everywhere is committed.
    var statusText: String? = nil
    let onOpenFilters: () -> Void

    /// Sprint toggles are staged here while the picker is open and committed
    /// once when it closes, so picking three sprints is one reload, not three.
    @State private var sprintDraft: [String]?

    var body: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    sprintControl
                    #if !os(macOS)
                    viewModeMenu
                    #endif
                    filterButton
                    ForEach(chips) { chip in
                        Button {
                            remove(chip)
                        } label: {
                            HStack(spacing: 4) {
                                Text(chip.text)
                                    .lineLimit(1)
                                Image(systemName: "xmark")
                                    .font(.caption2.weight(.semibold))
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.accentColor)
                        .help("Remove this filter")
                    }
                }
                .padding(.vertical, 1)
            }
            Spacer(minLength: 0)
            if let statusText {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if model.loadState == .loaded || !model.issues.isEmpty {
                Text("^[\(model.issues.count) issue](inflect: true)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            #if os(macOS)
            Button {
                model.reload()
            } label: {
                if model.loadState == .loading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .disabled(model.loadState == .loading)
            .help("Refresh (⌘R)")
            #endif
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Controls

    private var sprintControl: some View {
        KeyboardMultiSelect(
            title: "Sprints",
            options: model.availableSprints.map { MultiSelectOption(id: $0.name, label: $0.name) },
            selection: sprintSelection,
            shortcut: "s",
            shortcutModifiers: .shift,
            bordered: true,
            emptyLabel: "No sprint",
            summaryNoun: "sprints",
            onDismiss: commitSprintDraft
        )
    }

    private var committedSprints: [String] {
        model.availableSprints.map(\.name).filter { model.selectedSprintIDs.contains($0) }
    }

    private var sprintSelection: Binding<[String]> {
        Binding(
            get: { sprintDraft ?? committedSprints },
            set: { sprintDraft = $0 }
        )
    }

    private func commitSprintDraft() {
        guard let draft = sprintDraft else { return }
        sprintDraft = nil
        let next = Set(draft)
        if next != model.selectedSprintIDs {
            model.setSprintSelection(next)
        }
    }

    #if !os(macOS)
    private var viewModeMenu: some View {
        Menu {
            Picker("View", selection: $viewMode) {
                ForEach(IssueViewMode.allCases) { mode in
                    Label(mode.label, systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 4) {
                Text(viewMode.label)
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
    #endif

    private var filterButton: some View {
        let count = filterStore.definition.activeCount
        return Button(action: onOpenFilters) {
            Label("Filter", systemImage: count > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .keyboardShortcut("f", modifiers: [])
        .help(count > 0 ? "Filters (\(count) active) (F)" : "Filter (F)")
    }

    // MARK: - Chips

    private var chips: [FilterChip] {
        FilterChip.chips(for: filterStore.definition, options: model.filterOptions, currentUserName: currentUserName)
    }

    private func remove(_ chip: FilterChip) {
        switch filterStore.definition {
        case .jql:
            filterStore.clear()
        case .structured(var group):
            group.rows.removeAll { $0.id == chip.id }
            filterStore.definition = .structured(group)
        }
    }
}

/// One removable condition in the scope bar. `id` is the row it came from, or
/// a fixed id for a raw JQL filter (which is removed as a whole).
struct FilterChip: Identifiable, Hashable {
    let id: UUID
    let text: String

    static let jqlChipID = UUID(uuidString: "00000000-0000-0000-0000-00000000004A")!

    static func chips(
        for definition: FilterDefinition,
        options: AvailableFilterOptions,
        currentUserName: String?
    ) -> [FilterChip] {
        switch definition {
        case .jql(let raw):
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [] : [FilterChip(id: jqlChipID, text: "JQL")]
        case .structured(let group):
            return group.rows.map { row in
                switch row.node {
                case .condition(let condition):
                    return FilterChip(id: row.id, text: summary(condition, options: options, currentUserName: currentUserName))
                case .group(let sub):
                    return FilterChip(id: row.id, text: "^[\(countConditions(sub)) condition](inflect: true)")
                }
            }
        }
    }

    private static func countConditions(_ group: FilterGroup) -> Int {
        group.rows.reduce(0) { total, row in
            switch row.node {
            case .condition: return total + 1
            case .group(let sub): return total + countConditions(sub)
            }
        }
    }

    /// "Assignee is me", "Status is any of To Do, Blocked", "Due before 12 Sep".
    static func summary(_ condition: FilterCondition, options: AvailableFilterOptions, currentUserName: String?) -> String {
        let field = condition.field.displayName
        guard condition.op.needsValues else {
            return "\(field) \(condition.op.displayName)"
        }
        if condition.field == .assignee,
           condition.op == .isAnyOf,
           let me = currentUserName,
           condition.values == [me] {
            return "Assignee is me"
        }
        let names = condition.values.map { displayName(for: $0, field: condition.field, options: options) }
        let shown = names.prefix(2).joined(separator: ", ")
        let extra = names.count > 2 ? " +\(names.count - 2)" : ""
        let op: String
        if names.count == 1 {
            switch condition.op {
            case .isAnyOf: op = "is"
            case .isNoneOf: op = "is not"
            default: op = condition.op.displayName
            }
        } else {
            op = condition.op.displayName
        }
        return "\(field) \(op) \(shown)\(extra)"
    }

    private static func displayName(for value: String, field: FilterField, options: AvailableFilterOptions) -> String {
        switch field {
        case .status:
            return StatusNormaliser.normalise(value)
        case .assignee:
            if value == "UNASSIGNED" { return "Unassigned" }
            return options.assignees.first { $0.id == value }?.displayName ?? value
        case .reporter:
            return options.reporters.first { $0.id == value }?.displayName ?? value
        case .release:
            if value == "NO_RELEASE" { return "No release" }
            return options.releases.first { $0.id == value }?.displayName ?? value
        default:
            return value
        }
    }
}
