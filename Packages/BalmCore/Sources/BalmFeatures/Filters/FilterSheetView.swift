import SwiftUI
import BalmModels
import BalmAPI

/// Modal filter editor presented as a sheet on every platform. Edits a draft
/// `FilterDefinition` — a structured condition tree (the builder) or a raw-JQL
/// fragment (Advanced) — so the user can Cancel without side-effects. Apply
/// commits the draft to the store; Reset clears the draft only. Saved filters
/// are applied into / created from the draft.
public struct FilterSheetView: View {
    @Bindable var store: FilterStore
    @Bindable var savedStore: SavedFiltersStore
    let options: AvailableFilterOptions
    let sprints: [String]
    let onDismiss: () -> Void

    enum EditMode: String, CaseIterable, Identifiable {
        case structured, jql
        var id: String { rawValue }
        var label: String { self == .structured ? "Builder" : "Advanced (JQL)" }
    }

    @State private var mode: EditMode
    @State private var rootGroup: FilterGroup
    @State private var jqlText: String

    @State private var showingSaveAlert = false
    @State private var saveName = ""
    @State private var renameTarget: SavedFilter?
    @State private var renameText = ""

    public init(
        store: FilterStore,
        savedStore: SavedFiltersStore,
        options: AvailableFilterOptions,
        sprints: [String],
        onDismiss: @escaping () -> Void
    ) {
        self.store = store
        self.savedStore = savedStore
        self.options = options
        self.sprints = sprints
        self.onDismiss = onDismiss
        switch store.definition {
        case .structured(let group):
            _mode = State(initialValue: .structured)
            _rootGroup = State(initialValue: group)
            _jqlText = State(initialValue: "")
        case .jql(let raw):
            _mode = State(initialValue: .jql)
            _rootGroup = State(initialValue: FilterGroup())
            _jqlText = State(initialValue: raw)
        }
    }

    private var draft: FilterDefinition {
        switch mode {
        case .structured: return .structured(rootGroup)
        case .jql: return .jql(jqlText)
        }
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Picker("Mode", selection: $mode) {
                            ForEach(EditMode.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        Spacer()
                        savedMenu
                    }

                    if mode == .structured {
                        FilterBuilderView(group: $rootGroup, options: options)
                    } else {
                        AdvancedJQLView(jql: $jqlText, projectKey: store.projectKey, sprints: sprints)
                    }

                    if !draft.isEmpty {
                        Button(role: .destructive) { reset() } label: {
                            Label("Reset", systemImage: "arrow.uturn.backward")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding()
            }
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
                        store.definition = draft
                        onDismiss()
                    }
                    .disabled(draft == store.definition)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 580)
        #endif
        .onChange(of: mode) { _, newMode in
            // First switch to Advanced prefills the editor from the builder so
            // the user can tweak the compiled JQL. Switching back keeps the
            // builder tree (arbitrary JQL can't be parsed back into it).
            if newMode == .jql,
               jqlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !rootGroup.isEmpty {
                jqlText = JQLBuilder(
                    projectKey: store.projectKey,
                    sprints: [],
                    definition: .structured(rootGroup)
                ).discretionaryFragment() ?? ""
            }
        }
        .alert("Save Filter", isPresented: $showingSaveAlert) {
            TextField("Name", text: $saveName)
            Button("Save") { savedStore.save(name: saveName, definition: draft) }
                .disabled(saveName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Save the current filter to reuse later in this project.")
        }
        .alert("Rename Filter", isPresented: renameAlertBinding) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let target = renameTarget { savedStore.rename(target, to: renameText) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })
    }

    private var savedMenu: some View {
        Menu {
            if savedStore.savedFilters.isEmpty {
                Text("No saved filters")
            } else {
                ForEach(savedStore.savedFilters) { filter in
                    Button(filter.name) { apply(filter) }
                }
                Divider()
                Menu("Manage") {
                    ForEach(savedStore.savedFilters) { filter in
                        Menu(filter.name) {
                            Button("Update to current filter") {
                                savedStore.save(name: filter.name, definition: draft)
                            }
                            .disabled(draft.isEmpty || draft == filter.definition)
                            Button("Rename…") {
                                renameText = filter.name
                                renameTarget = filter
                            }
                            Button("Delete", role: .destructive) { savedStore.delete(filter) }
                        }
                    }
                }
            }
            Divider()
            Button("Save current as…") {
                saveName = ""
                showingSaveAlert = true
            }
            .disabled(draft.isEmpty)
        } label: {
            Label("Saved", systemImage: "bookmark")
        }
        .fixedSize()
    }

    private func apply(_ filter: SavedFilter) {
        switch filter.definition {
        case .structured(let group):
            rootGroup = group
            jqlText = ""
            mode = .structured
        case .jql(let raw):
            jqlText = raw
            mode = .jql
        }
    }

    private func reset() {
        rootGroup = FilterGroup()
        jqlText = ""
        mode = .structured
    }
}
