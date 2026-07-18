import SwiftUI
import BalmModels
import BalmAuth
import BalmAPI
import BalmDesignSystem
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public enum IssueViewMode: String, CaseIterable, Identifiable, Sendable {
    case list
    case board
    public var id: String { rawValue }
    var label: String { self == .list ? "List" : "Board" }
    var systemImage: String { self == .list ? "list.bullet" : "rectangle.split.3x1" }
}

public struct IssueListView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.balmTheme) private var theme

    /// iOS pushes detail via the shell's `openIssue`; macOS drives `selection`.
    @Environment(\.openIssue) private var openIssueAction

    @Binding private var selection: JiraIssue?
    private let onOpenSettings: (() -> Void)?
    @State private var model: IssueListViewModel
    @State private var filterStore: FilterStore
    @State private var savedFiltersStore: SavedFiltersStore
    @State private var showingSprintPicker = false
    @State private var showingNewIssue = false
    @State private var showingFiltersSheet = false
    @State private var searchText = ""
    @State private var searchPresented = false
    @State private var boardColumnID: String?
    @AppStorage private var viewModeRaw: String

    public init(
        project: JiraProject,
        selection: Binding<JiraIssue?>,
        onOpenSettings: (() -> Void)? = nil
    ) {
        self._selection = selection
        self.onOpenSettings = onOpenSettings
        let placeholderAPI = BalmAPI_PlaceholderForState.shared
        self._model = State(initialValue: IssueListViewModel(project: project, api: placeholderAPI.api))
        self._filterStore = State(initialValue: FilterStore(projectKey: project.key))
        self._savedFiltersStore = State(initialValue: SavedFiltersStore(projectKey: project.key))
        self._viewModeRaw = AppStorage(
            wrappedValue: IssueViewMode.list.rawValue,
            "issues.viewMode.\(project.key)"
        )
    }

    private var viewMode: IssueViewMode {
        IssueViewMode(rawValue: viewModeRaw) ?? .list
    }

    public var body: some View {
        #if os(macOS)
        macBody
        #else
        iosBody
        #endif
    }

    // MARK: - Mac: single-column main content. Filters are a sheet, detail is
    //         surfaced as an `.inspector` only when a row is selected.

    #if os(macOS)
    private var macBody: some View {
        NavigationStack {
            mainContent
                .inspector(isPresented: detailInspectorBinding) {
                    if let issue = selection {
                        IssueDetailView(issue: issue, onClose: { selection = nil })
                            .inspectorColumnWidth(min: 600, ideal: 780, max: 1040)
                    }
                }
        }
        .environment(\.openIssue, OpenIssueAction { selection = $0 })
        .toolbar { toolbarContent }
        .sheet(isPresented: $showingFiltersSheet) {
            FilterSheetView(
                store: filterStore,
                savedStore: savedFiltersStore,
                options: model.filterOptions,
                sprints: model.selectedSprintNames,
                onDismiss: { showingFiltersSheet = false }
            )
        }
        .applySharedModifiers(
            showingSprintPicker: $showingSprintPicker,
            showingNewIssue: $showingNewIssue,
            model: model,
            filterStore: filterStore,
            taskID: model.project.id,
            reconnect: reconnectAndLoad,
            onIssueCreated: handleCreated
        )
        .background { viewShortcutSink }
        .id(model.project.id)
    }

    /// Invisible buttons that own the 1/2 view-switch shortcuts. The segmented
    /// Picker can't carry per-option shortcuts, and single keys don't fire
    /// while a text field (the search bar) has focus.
    private var viewShortcutSink: some View {
        Group {
            Button("List view") { viewModeRaw = IssueViewMode.list.rawValue }
                .keyboardShortcut("1", modifiers: [])
            Button("Board view") { viewModeRaw = IssueViewMode.board.rawValue }
                .keyboardShortcut("2", modifiers: [])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    /// Open the inspector iff an issue is selected. Collapsing the inspector
    /// deselects, so it stays in sync with the list selection.
    private var detailInspectorBinding: Binding<Bool> {
        Binding(
            get: { selection != nil },
            set: { isShown in
                if !isShown { selection = nil }
            }
        )
    }
    #endif

    // MARK: - iOS / iPadOS: filters as bottom sheet

    private var iosBody: some View {
        mainContent
            .toolbar { toolbarContent }
            .sheet(isPresented: $showingFiltersSheet) {
                FilterSheetView(
                    store: filterStore,
                    savedStore: savedFiltersStore,
                    options: model.filterOptions,
                    sprints: model.selectedSprintNames,
                    onDismiss: { showingFiltersSheet = false }
                )
                .presentationDetents([.large])
            }
            .applySharedModifiers(
                showingSprintPicker: $showingSprintPicker,
                showingNewIssue: $showingNewIssue,
                model: model,
                filterStore: filterStore,
                taskID: model.project.id,
                reconnect: reconnectAndLoad,
                onIssueCreated: handleCreated
            )
            .id(model.project.id)
    }

    // MARK: - Shared content

    @ViewBuilder
    private var mainContent: some View {
        Group {
            switch model.loadState {
            case .idle:
                centred(ProgressView("Loading issues…"))
            case .loading where model.issues.isEmpty:
                centred(ProgressView("Loading issues…"))
            case .failed(let message):
                centred(Text(message).foregroundStyle(theme.palette.destructive))
            case .loaded where model.issues.isEmpty:
                centred(emptyState)
            default:
                content
            }
        }
        .navigationTitle(model.project.name)
        .searchable(text: $searchText, isPresented: $searchPresented, prompt: "Filter issues in view")
        .onSubmit(of: .search) {
            // ⌘K → type a key → Enter jumps straight to that ticket (even if
            // it isn't in the current view). Anything that isn't a key just
            // ends the search session with the in-view filter still applied.
            Task { await openTypedIssue() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .balmSearchRequested)) { _ in
            // Cmd+K focuses the inline filter rather than opening a modal.
            searchPresented = true
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        #if os(macOS)
        macToolbar
        #else
        iosToolbar
        #endif
    }

    private var viewModeBinding: Binding<IssueViewMode> {
        Binding(get: { viewMode }, set: { viewModeRaw = $0.rawValue })
    }

    #if !os(macOS)
    /// Compact iOS bar: search + new are primary; everything else folds into
    /// an overflow menu so the navigation bar isn't a wall of glyphs.
    @ToolbarContentBuilder
    private var iosToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                showingNewIssue = true
            } label: {
                Image(systemName: "plus")
            }
            Menu {
                Picker("View", selection: viewModeBinding) {
                    ForEach(IssueViewMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.systemImage).tag(mode)
                    }
                }
                .pickerStyle(.inline)
                Section {
                    Button {
                        showingSprintPicker = true
                    } label: {
                        Label("Sprints (\(model.selectedSprintIDs.count))", systemImage: "calendar")
                    }
                    Button(action: toggleFilters) {
                        let count = filterStore.definition.activeCount
                        Label(count > 0 ? "Filters (\(count))" : "Filters",
                              systemImage: "line.3.horizontal.decrease.circle")
                    }
                    Button { model.reload() } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.loadState == .loading)
                    if let onOpenSettings {
                        Button(action: onOpenSettings) {
                            Label("Settings", systemImage: "gearshape")
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }
    #endif

    @ToolbarContentBuilder
    private var macToolbar: some ToolbarContent {
        ToolbarItem {
            Picker("View", selection: viewModeBinding) {
                ForEach(IssueViewMode.allCases) { mode in
                    Label(mode.label, systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 110)
        }
        ToolbarItem {
            Button {
                showingSprintPicker = true
            } label: {
                Label("Sprints", systemImage: "calendar")
                    .labelStyle(.iconOnly)
            }
            .keyboardShortcut("s", modifiers: [])
            .help("Sprints (\(model.selectedSprintIDs.count)) — S")
        }
        ToolbarItem {
            Button(action: toggleFilters) {
                let count = filterStore.definition.activeCount
                Label(
                    "Filters",
                    systemImage: count > 0
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease.circle"
                )
                .labelStyle(.iconOnly)
            }
            .keyboardShortcut("f", modifiers: [])
            .help(filterStore.definition.activeCount > 0
                  ? "Filters (\(filterStore.definition.activeCount) active)"
                  : "Filters")
        }
        ToolbarItem {
            Button {
                showingNewIssue = true
            } label: {
                Label("New Issue", systemImage: "plus")
                    .labelStyle(.iconOnly)
            }
            .keyboardShortcut("a", modifiers: [])
            .help("New Issue — A")
        }
        ToolbarItem {
            Button { model.reload() } label: {
                if model.loadState == .loading {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(model.loadState == .loading)
            .help("Refresh (⌘R)")
        }
    }

    private func toggleFilters() {
        showingFiltersSheet.toggle()
    }

    /// Resolve the search text to an issue key and open it. Bare numbers are
    /// prefixed with the current project key (so "123" → "PROJ-123"). Text
    /// that isn't a key is left as a plain in-view filter.
    private func openTypedIssue() async {
        let raw = searchText.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { searchPresented = false; return }
        guard let key = normalisedIssueKey(raw) else {
            searchPresented = false
            return
        }
        if let issue = await model.fetchIssue(key: key) {
            selection = issue
            searchText = ""
            searchPresented = false
        }
    }

    private func normalisedIssueKey(_ text: String) -> String? {
        let upper = text.uppercased()
        if upper.contains("-") {
            // Full PROJ-123 shape.
            let isKey = upper.range(of: #"^[A-Z][A-Z0-9]+-\d+$"#, options: .regularExpression) != nil
            return isKey ? upper : nil
        }
        // Bare number → assume the current project.
        if upper.range(of: #"^\d+$"#, options: .regularExpression) != nil {
            return "\(model.project.key)-\(upper)"
        }
        return nil
    }

    /// Issues matching the live search text (key or summary). Empty query =
    /// everything currently loaded.
    private var filteredIssues: [JiraIssue] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return model.issues }
        return model.issues.filter {
            $0.key.lowercased().contains(q) || $0.summary.lowercased().contains(q)
        }
    }

    private var filteredColumns: [BoardColumn] {
        IssueListViewModel.columns(from: filteredIssues)
    }

    @ViewBuilder
    private var content: some View {
        switch viewMode {
        case .list:
            listBody
        case .board:
            BoardView(
                columns: filteredColumns,
                selection: $selection,
                columnSelection: $boardColumnID,
                onColumnViewed: { model.refreshInBackground() }
            ) { key, column in
                Task { await model.moveIssue(key: key, to: column) }
            }
            .onAppear { syncBoardColumnSelection() }
            .onChange(of: filteredColumns.map(\.id)) { _, _ in syncBoardColumnSelection() }
            .onChange(of: selection) { _, _ in syncBoardColumnSelection() }
        }
    }

    private func syncBoardColumnSelection() {
        boardColumnID = BoardColumnSelectionPolicy.preferredColumnID(
            current: boardColumnID,
            selectedIssue: selection,
            columns: filteredColumns
        )
    }

    private var listBody: some View {
        List(selection: $selection) {
            ForEach(filteredIssues, id: \.self) { issue in
                NavigationLink(value: issue) {
                    IssueRowView(issue: issue)
                }
                .simultaneousGesture(TapGesture().onEnded {
                    selection = issue
                    model.refreshInBackground()
                })
                .tag(issue)
            }
        }
        .animation(.spring(duration: 0.25), value: filteredIssues.map(\.id))
        .refreshable { await model.reloadAwaiting() }
    }

    /// Post-create: refresh the list so the new ticket is immediately visible,
    /// and raise a success toast with quick actions for it.
    private func handleCreated(key: String) {
        Task { await model.refreshAfterCreate(key: key) }
        env.toaster.success("Created \(key)", actions: [
            .init(title: "Copy \(key)") {
                setClipboard(key)
                env.toaster.info("Copied \(key)")
            },
            .init(title: "Open") {
                Task {
                    var issue = model.issues.first { $0.key == key }
                    if issue == nil { issue = await model.fetchIssue(key: key) }
                    if let issue { openCreatedIssue(issue) }
                }
            }
        ])
    }

    private func openCreatedIssue(_ issue: JiraIssue) {
        #if os(macOS)
        selection = issue
        #else
        openIssueAction(issue)
        #endif
    }

    private func setClipboard(_ string: String) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #elseif canImport(UIKit)
        UIPasteboard.general.string = string
        #endif
    }

    private func reconnectAndLoad() async {
        BalmAPI_PlaceholderForState.shared.api = env.api
        let real = IssueListViewModel(project: model.project, api: env.api, toaster: env.toaster)
        real.setUserDefinition(filterStore.definition)
        model = real
        await real.loadSprintsIfNeeded()
        real.reload()
    }

    private func centred<C: View>(_ content: C) -> some View {
        VStack { content }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: theme.spacing.m) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(theme.palette.mutedForeground)
            if model.selectedSprintIDs.isEmpty {
                Text("No sprints selected.")
                    .font(theme.typography.headline)
                    .foregroundStyle(theme.palette.foreground)
                Text("Pick at least one sprint or the backlog to see issues.")
                    .foregroundStyle(theme.palette.mutedForeground)
                    .multilineTextAlignment(.center)
                Button("Pick Sprints") { showingSprintPicker = true }
                    .buttonStyle(.borderedProminent)
            } else if !model.userDefinition.isEmpty {
                Text("No matches.")
                    .font(theme.typography.headline)
                    .foregroundStyle(theme.palette.foreground)
                Text("Adjust the filters or pick more sprints.")
                    .foregroundStyle(theme.palette.mutedForeground)
                    .multilineTextAlignment(.center)
            } else {
                Text("No issues in the selected sprint\(model.selectedSprintIDs.count == 1 ? "" : "s").")
                    .font(theme.typography.headline)
                    .foregroundStyle(theme.palette.foreground)
                Button("Pick Sprints") { showingSprintPicker = true }
                    .buttonStyle(.borderless)
            }
        }
        .padding(theme.spacing.xl)
    }
}

private extension View {
    /// Sheets, notification listeners, filter syncing, and task hooks that
    /// apply to both Mac and iOS layouts. Pulled out so the `body` reads
    /// cleanly on either platform.
    @MainActor
    func applySharedModifiers(
        showingSprintPicker: Binding<Bool>,
        showingNewIssue: Binding<Bool>,
        model: IssueListViewModel,
        filterStore: FilterStore,
        taskID: String,
        reconnect: @escaping () async -> Void,
        onIssueCreated: @escaping (String) -> Void
    ) -> some View {
        self
            .sheet(isPresented: showingSprintPicker) {
                SprintMultiSelectView(model: model)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: showingNewIssue) {
                NewIssueView(
                    project: model.project,
                    defaultSprint: model.availableSprints.first { model.selectedSprintIDs.contains($0.name) },
                    onCreated: { onIssueCreated($0.key) }
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .balmCreateIssueRequested)) { _ in
                showingNewIssue.wrappedValue = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .balmIssueUpdated)) { note in
                if let issue = note.userInfo?["issue"] as? JiraIssue {
                    model.applyExternalUpdate(issue)
                }
            }
            .task(id: taskID) {
                await reconnect()
            }
            .onChange(of: filterStore.definition) { _, next in
                model.setUserDefinition(next)
            }
    }
}

/// `@State` initialisers cannot read `@Environment`, so the VM bootstraps with
/// a placeholder `JiraClient` swapped to the live one in `.task`. Replace with
/// parent-injected client when feasible.
@MainActor
final class BalmAPI_PlaceholderForState {
    static let shared = BalmAPI_PlaceholderForState()
    var api: JiraClient = JiraClient(tokens: NullTokens())
}

struct NullTokens: TokenProvider {
    func snapshot() async throws -> AuthSnapshot {
        throw AuthError.refreshFailed(reason: "not signed in")
    }
    func invalidateAccessToken() async {}
}
