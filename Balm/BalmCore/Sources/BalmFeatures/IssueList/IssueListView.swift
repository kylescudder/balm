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

/// The content column: a scope bar over a list grouped by status health, or a
/// board. Selection is owned by the shell, which shows the issue in the Mac
/// inspector or the split view's detail column.
public struct IssueListView: View {
    @Environment(AppEnvironment.self) private var env

    @Binding private var selection: JiraIssue?
    private let onOpenSettings: (() -> Void)?
    /// Tells the shell why the selected issue was hidden from the view, so the
    /// inspector can say so and offer the one action that would show it.
    private let onVisibilityNote: ((IssueVisibilityNote?) -> Void)?
    private let filterStore: FilterStore
    private let savedFiltersStore: SavedFiltersStore
    @State private var model: IssueListViewModel
    @State private var showingNewIssue = false
    @State private var showingFiltersSheet = false
    @State private var searchText = ""
    @State private var searchPresented = false
    @State private var boardColumnID: String?
    @AppStorage private var viewModeRaw: String

    public init(
        project: JiraProject,
        filterStore: FilterStore,
        savedFiltersStore: SavedFiltersStore,
        selection: Binding<JiraIssue?>,
        onOpenSettings: (() -> Void)? = nil,
        onVisibilityNote: ((IssueVisibilityNote?) -> Void)? = nil
    ) {
        self._selection = selection
        self.onOpenSettings = onOpenSettings
        self.onVisibilityNote = onVisibilityNote
        self.filterStore = filterStore
        self.savedFiltersStore = savedFiltersStore
        let placeholderAPI = BalmAPI_PlaceholderForState.shared
        self._model = State(initialValue: IssueListViewModel(project: project, api: placeholderAPI.api))
        self._viewModeRaw = AppStorage(
            wrappedValue: IssueViewMode.list.rawValue,
            "issues.viewMode.\(project.key)"
        )
    }

    private var viewMode: IssueViewMode {
        IssueViewMode(rawValue: viewModeRaw) ?? .list
    }

    private var viewModeBinding: Binding<IssueViewMode> {
        Binding(get: { viewMode }, set: { viewModeRaw = $0.rawValue })
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScopeBar(
                model: model,
                filterStore: filterStore,
                viewMode: viewModeBinding,
                currentUserName: currentUserName,
                statusText: model.searchState == .idle ? nil : "Searching everywhere for \u{201C}\(committedQuery)\u{201D}",
                onOpenFilters: { showingFiltersSheet = true }
            )
            Divider()
            mainContent
                // Always claim the column, so an empty board or list cannot
                // shrink the stack and float the scope bar to the middle.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(model.project.name)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarTitleMenu { projectMenu }
        #endif
        .toolbar { toolbarContent }
        .searchable(text: $searchText, isPresented: $searchPresented, prompt: "Search issues")
        .onSubmit(of: .search) {
            Task { await submitSearch() }
        }
        .onChange(of: searchText) { _, next in
            model.invalidateSearchIfQueryChanged(next)
        }
        .onReceive(NotificationCenter.default.publisher(for: .balmSearchRequested)) { _ in
            searchPresented = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .balmToggleFiltersRequested)) { _ in
            showingFiltersSheet.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .balmRefreshIssuesRequested)) { _ in
            model.reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .balmCreateIssueRequested)) { _ in
            showingNewIssue = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .balmIssueUpdated)) { note in
            if let issue = note.userInfo?["issue"] as? JiraIssue {
                model.applyExternalUpdate(issue)
            }
        }
        .sheet(isPresented: $showingFiltersSheet) {
            FilterSheetView(
                store: filterStore,
                savedStore: savedFiltersStore,
                options: model.filterOptions,
                sprints: model.selectedSprintNames,
                onDismiss: { showingFiltersSheet = false }
            )
            #if !os(macOS)
            .presentationDetents([.large])
            #endif
        }
        .sheet(isPresented: $showingNewIssue) {
            NewIssueView(
                project: model.project,
                defaultSprint: model.availableSprints.first { model.selectedSprintIDs.contains($0.name) },
                onCreated: { handleCreated(key: $0.key) }
            )
        }
        .task(id: model.project.id) {
            await reconnectAndLoad()
        }
        .onChange(of: filterStore.definition) { _, next in
            model.setUserDefinition(next)
            publishVisibilityNote()
        }
        .onChange(of: selection) { _, _ in publishVisibilityNote() }
        .onChange(of: model.searchState) { _, _ in publishVisibilityNote() }
        .onChange(of: model.selectedSprintIDs) { _, _ in publishVisibilityNote() }
        #if os(macOS)
        .background { viewShortcutSink }
        #endif
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        #if os(macOS)
        // `.automatic`, not `.primaryAction`: on macOS 26 the toolbar is split
        // into per-column zones and primary actions are forced to the trailing
        // zone, which is the inspector's when it is open. Automatic keeps these
        // over the list where they belong.
        ToolbarItemGroup(placement: .automatic) {
            Picker("View", selection: viewModeBinding) {
                ForEach(IssueViewMode.allCases) { mode in
                    Label(mode.label, systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help("List (1), Board (2)")
            Button {
                showingNewIssue = true
            } label: {
                Label("New issue", systemImage: "plus")
            }
            .help("New issue (N)")
        }
        #else
        if let onOpenSettings {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: onOpenSettings) {
                    AvatarView(name: currentUserName, avatarURL: currentUserAvatar, size: 28)
                }
                .accessibilityLabel("Settings")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                showingNewIssue = true
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("New issue")
        }
        #endif
    }

    #if !os(macOS)
    @ViewBuilder
    private var projectMenu: some View {
        ForEach(env.projectListStore.projects) { project in
            Button {
                env.activeProjectStore.set(project)
            } label: {
                if project.id == model.project.id {
                    Label(project.name, systemImage: "checkmark")
                } else {
                    Text(project.name)
                }
            }
        }
    }
    #endif

    #if os(macOS)
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
    #endif

    // MARK: - Content

    @ViewBuilder
    private var mainContent: some View {
        if model.searchState != .idle {
            searchResults
        } else {
            switch model.loadState {
            case .idle:
                centred(ProgressView("Loading issues"))
            case .loading where model.issues.isEmpty:
                centred(ProgressView("Loading issues"))
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't load issues", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { model.reload() }
                }
            case .loaded where model.issues.isEmpty:
                emptyState
            default:
                if isFilteringLocally && filteredIssues.isEmpty {
                    noLocalMatches
                } else {
                    content
                }
            }
        }
    }

    private var isFilteringLocally: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Typed text matched nothing in the loaded view. Return runs the search
    /// across every project, so say so rather than showing an empty board.
    private var noLocalMatches: some View {
        ContentUnavailableView {
            Label("No matches in this view", systemImage: "magnifyingglass")
        } description: {
            Text("Press Return to search every project for \u{201C}\(searchText.trimmingCharacters(in: .whitespaces))\u{201D}.")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewMode {
        case .list:
            listBody
        case .board:
            BoardView(
                columns: filteredColumns,
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

    private var listBody: some View {
        List(selection: $selection) {
            ForEach(IssueListViewModel.healthSections(from: filteredIssues)) { section in
                Section {
                    ForEach(section.issues, id: \.self) { issue in
                        IssueRowView(issue: issue)
                            .tag(issue)
                    }
                } header: {
                    sectionHeader(section)
                }
            }
        }
        .listStyle(platformListStyle)
        .animation(.spring(duration: 0.25), value: filteredIssues.map(\.id))
        .refreshable { await model.reloadAwaiting() }
    }

    private func sectionHeader(_ section: IssueHealthSection) -> some View {
        HStack(spacing: 6) {
            StatusGlyph(spec: section.health.representativeGlyph, size: 12)
            Text(section.health.title)
            Text(section.issues.count, format: .number)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .textCase(nil)
    }

    private var platformListStyle: some ListStyle {
        #if os(macOS)
        return .inset
        #else
        return .insetGrouped
        #endif
    }

    private func syncBoardColumnSelection() {
        boardColumnID = BoardColumnSelectionPolicy.preferredColumnID(
            current: boardColumnID,
            selectedIssue: selection,
            columns: filteredColumns
        )
    }

    // MARK: - Search

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
    /// body. Empty query = everything currently loaded.
    private var filteredIssues: [JiraIssue] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return model.issues }
        return model.issues.filter {
            $0.key.lowercased().contains(q)
                || $0.summary.lowercased().contains(q)
                || ($0.descriptionText?.lowercased().contains(q) ?? false)
        }
    }

    /// Global search hits that aren't already in the in-view list.
    private var globalExtras: [JiraIssue] {
        guard !model.globalResults.isEmpty else { return [] }
        let localKeys = Set(filteredIssues.map(\.key))
        return model.globalResults.filter { !localKeys.contains($0.key) }
    }

    private var filteredColumns: [BoardColumn] {
        IssueListViewModel.columns(from: filteredIssues)
    }

    @ViewBuilder
    private var searchResults: some View {
        let hasLocal = !filteredIssues.isEmpty
        switch model.searchState {
        case .idle:
            EmptyView()
        case .searching where !hasLocal:
            centred(ProgressView("Searching all projects"))
        case .failed(let message) where !hasLocal:
            ContentUnavailableView {
                Label("Couldn't search", systemImage: "exclamationmark.triangle")
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
                Section {
                    ForEach(filteredIssues, id: \.self) { issue in
                        IssueRowView(issue: issue)
                            .tag(issue)
                    }
                } header: {
                    resultsHeader(systemImage: "list.bullet", title: "In this view", count: filteredIssues.count)
                }
            }
            switch model.searchState {
            case .idle:
                EmptyView()
            case .searching:
                Section {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Searching all projects")
                            .foregroundStyle(.secondary)
                    }
                }
            case .failed(let message):
                Section {
                    Text(message).foregroundStyle(.red)
                }
            case .loaded:
                if hiddenGroups.isEmpty {
                    Section {
                        Text("No other matches across your projects.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(hiddenGroups) { group in
                        Section {
                            ForEach(group.results) { result in
                                HiddenResultRow(
                                    issue: result.issue,
                                    systemImage: group.kind.systemImage,
                                    detail: reasonText(for: result)
                                )
                                .tag(result.issue)
                            }
                        } header: {
                            resultsHeader(
                                systemImage: group.kind.systemImage,
                                title: group.kind.title,
                                count: group.results.count,
                                action: group.kind == .filtered ? ("Clear filters", { filterStore.clear() }) : nil
                            )
                        }
                    }
                }
            }
        }
        .listStyle(platformListStyle)
    }

    private func resultsHeader(
        systemImage: String,
        title: String,
        count: Int,
        action: (String, () -> Void)? = nil
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(.tertiary)
            Text(title)
            Text(count, format: .number)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer(minLength: 8)
            if let action {
                Button(action.0, action: action.1)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }
        }
        .textCase(nil)
    }

    // MARK: - Hidden result reasons

    private var committedQuery: String {
        searchText.trimmingCharacters(in: .whitespaces)
    }

    private var searchScope: SearchScope {
        SearchScope(
            activeProjectKey: model.project.key,
            selectedSprintNames: model.selectedSprintNames,
            loadedKeys: Set(model.issues.map(\.key)),
            definition: filterStore.definition
        )
    }

    private var hiddenGroups: [HiddenGroup] {
        SearchTriage.groups(for: globalExtras, scope: searchScope)
    }

    /// One line under a hidden result saying exactly why it was not in view.
    private func reasonText(for result: HiddenResult) -> String {
        switch result.reason {
        case .otherProject(let key):
            return "In \(projectName(forKey: key))"
        case .outsideSprints(let name):
            guard let name else { return "In the backlog" }
            if let sprint = result.issue.sprint, sprint.state.lowercased() == "closed" {
                if let completed = sprint.completeDate {
                    let formatter = RelativeDateTimeFormatter()
                    return "In \(name), closed \(formatter.localizedString(for: completed, relativeTo: Date()))"
                }
                return "In \(name), a closed sprint"
            }
            return "In \(name), not one of your selected sprints"
        case .filtered(let mismatch):
            switch mismatch {
            case .conditions(let conditions):
                if conditions.count == 1,
                   let condition = conditions.first,
                   condition.field == .assignee,
                   condition.op == .isAnyOf,
                   let me = currentUserName,
                   condition.values == [me] {
                    if let assignee = result.issue.assignee {
                        return "Assigned to \(assignee.displayName), not you"
                    }
                    return "Unassigned, not you"
                }
                let summaries = conditions.map {
                    FilterChip.summary($0, options: model.filterOptions, currentUserName: currentUserName)
                }
                return "Excluded by \(summaries.joined(separator: ", "))"
            case .jql:
                return "Excluded by your JQL filter"
            case .whole:
                return "Excluded by your filters"
            }
        case .matchedElsewhere(let loaded):
            return loaded
                ? "In your view. The match is in comments or a field the live filter does not search."
                : "In your view but not loaded yet. Refresh to see it."
        }
    }

    private func projectName(forKey key: String) -> String {
        env.projectListStore.projects.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.name ?? key
    }

    /// Builds the inspector note for the current selection, or clears it when
    /// the selection is in view or no search is committed.
    private func publishVisibilityNote() {
        guard let onVisibilityNote else { return }
        guard model.searchState != .idle,
              let issue = selection,
              !filteredIssues.contains(where: { $0.key == issue.key }),
              globalExtras.contains(where: { $0.key == issue.key })
        else {
            onVisibilityNote(nil)
            return
        }
        let result = HiddenResult(issue: issue, reason: SearchTriage.reason(for: issue, scope: searchScope))
        onVisibilityNote(visibilityNote(for: result))
    }

    private func visibilityNote(for result: HiddenResult) -> IssueVisibilityNote {
        let detail = reasonText(for: result)
        var actionTitle: String?
        var action: (() -> Void)?
        switch result.reason {
        case .otherProject(let key):
            if let project = env.projectListStore.projects.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame }) {
                actionTitle = "Switch to \(project.name)"
                action = { env.activeProjectStore.set(project) }
            }
        case .outsideSprints(let name):
            let target = name ?? JiraSprint.backlog.name
            if model.availableSprints.contains(where: { $0.name == target }) {
                actionTitle = name == nil ? "Add backlog" : "Add \(target)"
                action = { model.setSprintSelection(model.selectedSprintIDs.union([target])) }
            }
        case .filtered:
            actionTitle = "Clear filters"
            action = { filterStore.clear() }
        case .matchedElsewhere(let loaded):
            if !loaded {
                actionTitle = "Refresh"
                action = { model.reload() }
            }
        }
        return IssueVisibilityNote(
            systemImage: result.reason.group.systemImage,
            text: "Not in your view. \(detail)",
            actionTitle: actionTitle,
            action: action
        )
    }

    // MARK: - Empty states

    @ViewBuilder
    private var emptyState: some View {
        if model.selectedSprintIDs.isEmpty {
            ContentUnavailableView {
                Label("No sprint selected", systemImage: "calendar")
            } description: {
                #if os(macOS)
                Text("Choose a sprint in the bar above, or press ⇧S.")
                #else
                Text("Choose a sprint in the bar above.")
                #endif
            }
        } else if !model.userDefinition.isEmpty {
            ContentUnavailableView {
                Label("No matches", systemImage: "line.3.horizontal.decrease")
            } description: {
                Text("Nothing in the selected sprint matches these filters.")
            } actions: {
                Button("Clear filters") { filterStore.clear() }
            }
        } else {
            ContentUnavailableView {
                Label("Nothing here", systemImage: "tray")
            } description: {
                Text(model.selectedSprintIDs.count == 1
                     ? "No issues in this sprint."
                     : "No issues in the selected sprints.")
            }
        }
    }

    // MARK: - Helpers

    private var currentUserName: String? {
        if case .signedIn(_, _, let user) = env.authState { return user?.displayName }
        return nil
    }

    private var currentUserAvatar: URL? {
        if case .signedIn(_, _, let user) = env.authState { return user?.avatarUrls?.bestAvailable }
        return nil
    }

    /// Post-create: refresh the list so the new ticket is immediately visible,
    /// and raise a success toast with quick actions for it.
    private func handleCreated(key: String) {
        Task { await model.refreshAfterCreate(key: key) }
        env.toaster.success("Created \(key)", actions: [
            .init(title: "Copy") {
                setClipboard(key)
                env.toaster.info("Copied \(key)")
            },
            .init(title: "Open") {
                Task {
                    var issue = model.issues.first { $0.key == key }
                    if issue == nil { issue = await model.fetchIssue(key: key) }
                    if let issue { selection = issue }
                }
            }
        ])
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

/// A search hit that was not in the view: the normal row, plus one quiet line
/// underneath saying why.
struct HiddenResultRow: View {
    let issue: JiraIssue
    let systemImage: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            IssueRowView(issue: issue)
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.leading, 24)
            .padding(.bottom, 2)
        }
        .accessibilityElement(children: .combine)
    }
}
