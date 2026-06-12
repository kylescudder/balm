import SwiftUI
import BalmModels

/// Modal filter editor presented as a sheet on every platform. Edits a draft
/// copy of `FilterStore.filters` so the user can Cancel without side-effects.
/// Apply commits the draft back to the store; Reset wipes the draft only.
public struct FilterSheetView: View {
    @Bindable var store: FilterStore
    let options: AvailableFilterOptions
    let onDismiss: () -> Void

    @State private var draft: FilterOptions

    public init(
        store: FilterStore,
        options: AvailableFilterOptions,
        onDismiss: @escaping () -> Void
    ) {
        self.store = store
        self.options = options
        self.onDismiss = onDismiss
        _draft = State(initialValue: store.filters)
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Status") {
                    KeyboardSelectMenu(
                        title: "Status",
                        options: statusOptions(options.statuses),
                        selection: $draft.status,
                        shortcut: "s"
                    )
                }
                Section("Priority") {
                    KeyboardSelectMenu(
                        title: "Priority",
                        options: stringOptions(options.priorities),
                        selection: $draft.priority,
                        shortcut: "p"
                    )
                }
                Section("People") {
                    KeyboardSelectMenu(
                        title: "Assignee",
                        options: namedOptions(options.assignees),
                        selection: $draft.assignee,
                        shortcut: "a"
                    )
                    KeyboardSelectMenu(
                        title: "Reporter",
                        options: namedOptions(options.reporters),
                        selection: $draft.reporter
                    )
                }
                Section("Type & Release") {
                    KeyboardSelectMenu(
                        title: "Type",
                        options: stringOptions(options.issueTypes),
                        selection: $draft.issueType,
                        shortcut: "t"
                    )
                    KeyboardSelectMenu(
                        title: "Release",
                        options: namedOptions(options.releases),
                        selection: $draft.release
                    )
                }
                Section("Tags") {
                    KeyboardSelectMenu(
                        title: "Labels",
                        options: stringOptions(options.labels),
                        selection: $draft.labels,
                        shortcut: "l"
                    )
                    KeyboardSelectMenu(
                        title: "Components",
                        options: stringOptions(options.components),
                        selection: $draft.components,
                        shortcut: "c"
                    )
                }
                Section("Due Date") {
                    DueDateRangeRow(
                        from: $draft.dueDateFrom,
                        to: $draft.dueDateTo
                    )
                }
                if draft.activeCount > 0 {
                    Section {
                        Button(role: .destructive) {
                            draft = .empty
                        } label: {
                            HStack {
                                Spacer()
                                Text("Reset")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Filter")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        store.filters = draft
                        onDismiss()
                    }
                    .disabled(draft == store.filters)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 520)
    }

    private func stringOptions(_ values: [String]) -> [MultiSelectOption] {
        values.map { MultiSelectOption(id: $0, label: $0) }
    }

    /// Like `stringOptions` but pipes labels through `StatusNormaliser` so the
    /// menu reads "Awaiting Testing" instead of "AWAITING TESTING". The `id`
    /// stays as the raw tenant value so JQL still matches.
    private func statusOptions(_ values: [String]) -> [MultiSelectOption] {
        values
            .map { MultiSelectOption(id: $0, label: StatusNormaliser.normalise($0)) }
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    private func namedOptions(_ values: [AvailableFilterOptions.NamedOption]) -> [MultiSelectOption] {
        values.map { MultiSelectOption(id: $0.id, label: $0.displayName) }
    }
}

// MARK: - Due date range row

/// Two-row date range editor. Each side has a Toggle that reveals a
/// `DatePicker` when enabled. Persists as ISO `yyyy-MM-dd` strings.
struct DueDateRangeRow: View {
    @Binding var from: String?
    @Binding var to: String?

    @State private var fromDate: Date = .now
    @State private var toDate: Date = .now
    @State private var hasFrom: Bool = false
    @State private var hasTo: Bool = false

    init(from: Binding<String?>, to: Binding<String?>) {
        self._from = from
        self._to = to
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        if let raw = from.wrappedValue, let date = parser.date(from: raw) {
            _fromDate = State(initialValue: date)
            _hasFrom = State(initialValue: true)
        }
        if let raw = to.wrappedValue, let date = parser.date(from: raw) {
            _toDate = State(initialValue: date)
            _hasTo = State(initialValue: true)
        }
    }

    var body: some View {
        Group {
            Toggle("From", isOn: $hasFrom)
            if hasFrom {
                DatePicker("From date", selection: $fromDate, displayedComponents: .date)
                    .labelsHidden()
            }
            Toggle("To", isOn: $hasTo)
            if hasTo {
                DatePicker("To date", selection: $toDate, displayedComponents: .date)
                    .labelsHidden()
            }
        }
        .onChange(of: hasFrom) { _, _ in apply() }
        .onChange(of: hasTo) { _, _ in apply() }
        .onChange(of: fromDate) { _, _ in apply() }
        .onChange(of: toDate) { _, _ in apply() }
    }

    private func apply() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        from = hasFrom ? formatter.string(from: fromDate) : nil
        to = hasTo ? formatter.string(from: toDate) : nil
    }
}
