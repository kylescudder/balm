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
            if model.searchState != .idle {
                // A global search has been committed — the content area becomes a
                // native search-results presentation, taking over from the
                // board/list (and any load/empty state) until the field clears.
                searchResults
            } else {
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
        }
        .navigationTitle(model.project.name)
        .searchable(text: $searchText, isPresented: $searchPresented, prompt: "Filter in view · ↵ searches everywhere")
        .onSubmit(of: .search) {
            // ⌘K → type a key → Enter jumps straight to that ticket (even if
            // it isn't in the current view). Any other term runs an
            // instance-wide search whose hits show under "More results".
            Task { await submitSearch() }
        }
        .onChange(of: searchText) { _, next in
            // Emptying the field drops the global results and restores the
            // plain sprint/filter list.
            if next.trimmingCharacters(in: .whitespaces).isEmpty {
                model.clearSearch()
            }
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

    /// Handle ↵ in the search bar. A term that resolves to an issue key (a full
    /// `PROJ-123`, or a bare number assumed to be the current project) jumps
    /// straight to that ticket. Anything else runs an instance-wide search whose
    /// hits render under "More results".
    private func submitSearch() async {
        let raw = searchText.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { searchPresented = false; return }
        if let key = IssueKey.normalise(raw, projectKey: model.project.key) {
            if let issue = await model.fetchIssue(key: key) {
                selection = issue
                searchText = ""
                searchPresented = false
            }
            return
        }
        await model.search(raw)
    }

    /// Issues in the loaded view matching the live search text — key, title, or
    /// body. Empty query = everything currently loaded. This is the instant,
    /// no-network filter; ↵ then reaches beyond the view via `model.search`.
    private var filteredIssues: [JiraIssue] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return model.issues }
        return model.issues.filter {
            $0.key.lowercased().contains(q)
                || $0.summary.lowercased().contains(q)
                || ($0.descriptionText?.lowercased().contains(q) ?? false)
        }
    }

    /// Global search hits that aren't already in the in-view list, deduped by
    /// key — the "More results" set.
    private var globalExtras: [JiraIssue] {
        guard !model.globalResults.isEmpty else { return [] }
        let localKeys = Set(filteredIssues.map(\.key))
        return model.globalResults.filter { !localKeys.contains($0.key) }
    }

    /// Board columns for the in-view (locally filtered) issues. Global search
    /// hits never appear here — while a search is committed the whole content
    /// area switches to `searchResults` instead.
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
                #if os(macOS)
                NavigationLink(value: issue) {
                    IssueRowView(issue: issue)
                }
                .simultaneousGesture(TapGesture().onEnded {
                    selection = issue
                    model.refreshInBackground()
                })
                .tag(issue)
                #else
                Button {
                    selection = issue
                    openIssueAction(issue)
                } label: {
                    IssueRowView(issue: issue)
                }
                .buttonStyle(.plain)
                #endif
            }
        }
        .animation(.spring(duration: 0.25), value: filteredIssues.map(\.id))
        .refreshable { await model.reloadAwaiting() }
    }

    // MARK: - Global search results (shared by list & board while searching)

    /// The committed-search presentation: in-view matches and instance-wide hits
    /// as a native sectioned `List`, with `ContentUnavailableView` for the empty
    /// and failed states. Replaces the board/list — search is its own mode, not
    /// a column, so board and list surface out-of-view matches identically.
    @ViewBuilder
    private var searchResults: some View {
        let hasLocal = !filteredIssues.isEmpty
        switch model.searchState {
        case .idle:
            EmptyView()
        case .searching where !hasLocal:
            centred(ProgressView("Searching all projects…"))
        case .failed(let message) where !hasLocal:
            ContentUnavailableView {
                Label("Couldn’t search", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            }
        case .loaded where !hasLocal && globalExtras.isEmpty:
            ContentUnavailableView.search(text: searchText)
        default:
            searchResultsList(hasLocal: hasLocal)
        }
    }

    private func searchResultsList(hasLocal: Bool) -> some View {
        List(selection: $selection) {
            if hasLocal {
                Section("In current view") {
                    ForEach(filteredIssues, id: \.self) { issue in
                        NavigationLink(value: issue) {
                            IssueRowView(issue: issue)
                        }
                        .tag(issue)
                    }
                }
            }
            moreResultsSection
        }
    }

    /// The instance-wide section: hits not already shown in view, plus the
    /// search's in-flight / error / empty states rendered inline.
    @ViewBuilder
    private var moreResultsSection: some View {
        Section("More results") {
            switch model.searchState {
            case .idle:
                EmptyView()
            case .searching:
                HStack(spacing: theme.spacing.s) {
                    ProgressView().controlSize(.small)
                    Text("Searching all projects…")
                        .foregroundStyle(theme.palette.mutedForeground)
                }
            case .failed(let message):
                Text(message).foregroundStyle(theme.palette.destructive)
            case .loaded:
                if globalExtras.isEmpty {
                    Text("No other matches across your projects.")
                        .foregroundStyle(theme.palette.mutedForeground)
                } else {
                    ForEach(globalExtras, id: \.self) { issue in
                        NavigationLink(value: issue) {
                            IssueRowView(issue: issue)
                        }
                        .tag(issue)
                    }
                }
            }
        }
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
