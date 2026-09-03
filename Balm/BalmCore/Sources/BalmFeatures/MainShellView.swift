import SwiftUI
import BalmModels
import BalmDesignSystem

/// Filter state for the active project. Recreated whenever the project changes
/// so a different project never inherits another's filter or saved views.
@MainActor
struct ProjectStores {
    let projectKey: String
    let filter: FilterStore
    let saved: SavedFiltersStore

    init(projectKey: String) {
        self.projectKey = projectKey
        self.filter = FilterStore(projectKey: projectKey)
        self.saved = SavedFiltersStore(projectKey: projectKey)
    }
}

/// The places on iOS and iPadOS. Issues, Inbox and Search are tabs; projects
/// and saved views appear only in the iPad sidebar.
enum AppTab: Hashable {
    case issues
    case inbox
    case search
    case project(String)
    case view(UUID)
}

/// The app shell. macOS: a sidebar of places, the list or board in the middle,
/// and the issue in an inspector that works over both. iOS and iPadOS: a tab
/// view that becomes a sidebar on iPad, with detail in a split view.
public struct MainShellView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedIssue: JiraIssue?
    @State private var visibilityNote: IssueVisibilityNote?
    @State private var inboxIssue: JiraIssue?
    @State private var stores: ProjectStores?
    @State private var clearFilterOnNextProject = false
    @State private var showingProjectChooser = false
    @State private var showingSettings = false

    #if os(macOS)
    @State private var sidebarSelection: SidebarItem?
    @State private var inspectorPresented = true
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    #else
    @State private var tab: AppTab = .issues
    #endif

    public init() {}

    public var body: some View {
        Group {
            if let project = env.activeProjectStore.project {
                if let stores, stores.projectKey == project.key {
                    shell(project: project, stores: stores)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ProjectChooserView(isFirstRun: true)
            }
        }
        .environment(\.openIssue, OpenIssueAction { open($0) })
        .onChange(of: env.activeProjectStore.project?.key, initial: true) { _, key in
            projectChanged(key: key)
        }
        .sheet(isPresented: $showingProjectChooser) {
            ProjectChooserView(isFirstRun: false)
                .environment(env)
                .themed()
        }
        .onReceive(NotificationCenter.default.publisher(for: .balmChangeProjectRequested)) { _ in
            showingProjectChooser = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .balmSignOutRequested)) { _ in
            Task { await env.signOut() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .balmGoToInboxRequested)) { _ in
            goToInbox()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    // A transient failure at launch can leave the current
                    // user (and so the inbox poll) never started; foreground
                    // is the natural point to retry — a no-op once it's up.
                    await env.fetchCurrentUserIfNeeded()
                    await env.inboxStore.syncNow()
                }
            }
        }
    }

    // MARK: - Shared behaviour

    private func projectChanged(key: String?) {
        selectedIssue = nil
        inboxIssue = nil
        guard let key else {
            stores = nil
            return
        }
        let next = ProjectStores(projectKey: key)
        if clearFilterOnNextProject {
            next.filter.clear()
            clearFilterOnNextProject = false
        }
        stores = next
        #if os(macOS)
        if sidebarSelection != .inbox, let id = env.activeProjectStore.project?.id {
            sidebarSelection = .project(id)
        }
        #endif
    }

    /// Presents an issue wherever the current surface shows detail: the Mac
    /// inspector, or the detail column of whichever tab is up on iOS.
    private func open(_ issue: JiraIssue) {
        visibilityNote = nil
        #if os(macOS)
        selectedIssue = issue
        inspectorPresented = true
        #else
        switch tab {
        case .inbox:
            inboxIssue = issue
        case .search:
            tab = .issues
            selectedIssue = issue
        default:
            selectedIssue = issue
        }
        #endif
    }

    private func goToInbox() {
        #if os(macOS)
        sidebarSelection = .inbox
        #else
        tab = .inbox
        #endif
    }

    private var currentUserName: String? {
        if case .signedIn(_, _, let user) = env.authState { return user?.displayName }
        return nil
    }

    /// Everything assigned to the signed-in user, as a structured filter so the
    /// scope bar can show and remove it like any other condition. Assignee
    /// values are display names throughout the filter system (the issue
    /// payload carries no account id), so this matches that convention.
    static func myIssuesDefinition(displayName: String) -> FilterDefinition {
        .structured(FilterGroup(rows: [
            FilterRow(node: .condition(FilterCondition(field: .assignee, op: .isAnyOf, values: [displayName])))
        ]))
    }

    /// Reacts to a sidebar or tab-sidebar choice. Projects switch the active
    /// project (or clear the filter when already active); views and My issues
    /// apply a filter to the active project.
    private func handlePlace(_ item: SidebarItem, project: JiraProject, stores: ProjectStores) {
        switch item {
        case .inbox:
            break
        case .myIssues:
            if let me = currentUserName {
                stores.filter.definition = Self.myIssuesDefinition(displayName: me)
            }
        case .project(let id):
            if id == project.id {
                stores.filter.clear()
            } else if let target = env.projectListStore.project(id: id) {
                clearFilterOnNextProject = true
                env.activeProjectStore.set(target)
            }
        case .view(let id):
            if let saved = stores.saved.savedFilters.first(where: { $0.id == id }) {
                stores.filter.definition = saved.definition
            }
        }
    }

    @ViewBuilder
    private func shell(project: JiraProject, stores: ProjectStores) -> some View {
        #if os(macOS)
        macShell(project: project, stores: stores)
        #else
        adaptiveShell(project: project, stores: stores)
        #endif
    }

    // MARK: - macOS

    #if os(macOS)
    private func macShell(project: JiraProject, stores: ProjectStores) -> some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $sidebarSelection, savedFilters: stores.saved.savedFilters)
                .navigationSplitViewColumnWidth(min: 200, ideal: 224, max: 320)
        } detail: {
            NavigationStack {
                if sidebarSelection == .inbox {
                    InboxListView(openedIssueKey: selectedIssue?.key, onOpen: open)
                } else {
                    IssueListView(
                        project: project,
                        filterStore: stores.filter,
                        savedFiltersStore: stores.saved,
                        selection: $selectedIssue,
                        onVisibilityNote: { visibilityNote = $0 }
                    )
                    .id(project.id)
                }
            }
        }
        .inspector(isPresented: $inspectorPresented) {
            inspectorContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .inspectorColumnWidth(min: 380, ideal: 460, max: 560)
                // The inspector is a reading pane, so it is opaque rather than
                // the translucent glass macOS 26 gives it by default. The frame
                // above makes the background cover the whole pane, not just
                // the empty state's own box.
                .background(BalmSurface.window)
                .toolbar {
                    ToolbarItem {
                        Button {
                            inspectorPresented.toggle()
                        } label: {
                            Label("Inspector", systemImage: "sidebar.trailing")
                        }
                        .keyboardShortcut("i", modifiers: [.command, .option])
                        .help("Show or hide the inspector (⌥⌘I)")
                    }
                }
        }
        .onChange(of: sidebarSelection) { previous, item in
            // The first selection is the shell restoring the active project;
            // only a change made after that is a choice to act on.
            guard let item, previous != nil else { return }
            handlePlace(item, project: project, stores: stores)
        }
        .onChange(of: selectedIssue) { _, issue in
            // Picking a row (list, board or inbox) brings the pane back if it
            // was closed with the close button.
            if issue != nil { inspectorPresented = true }
        }
        .background { inboxShortcutSink }
    }

    @ViewBuilder
    private var inspectorContent: some View {
        if let issue = selectedIssue {
            IssueDetailView(issue: issue, note: visibilityNote, onClose: closeInspector)
                .id(issue.key)
        } else {
            EmptyInspectorView()
        }
    }

    /// Close means close: deselect and collapse the pane, rather than leaving
    /// an empty inspector open.
    private func closeInspector() {
        selectedIssue = nil
        inspectorPresented = false
    }

    /// Invisible button owning the bare-`I` inbox shortcut. Single keys don't
    /// fire while a text field (the search bar) has focus, which is the
    /// behaviour we want.
    private var inboxShortcutSink: some View {
        Button("Inbox") {
            sidebarSelection = .inbox
        }
        .keyboardShortcut("i", modifiers: [])
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
    #endif

    // MARK: - iOS / iPadOS

    #if !os(macOS)
    private func adaptiveShell(project: JiraProject, stores: ProjectStores) -> some View {
        TabView(selection: $tab) {
            Tab("Issues", systemImage: "list.bullet", value: AppTab.issues) {
                issuesTab(project: project, stores: stores)
            }
            Tab("Inbox", systemImage: "tray", value: AppTab.inbox) {
                inboxTab
            }
            .badge(env.inboxStore.unreadCount)
            Tab(value: AppTab.search, role: .search) {
                GlobalSearchView(project: project)
            }

            TabSection("Projects") {
                ForEach(env.projectListStore.projects) { candidate in
                    Tab(candidate.name, systemImage: "folder", value: AppTab.project(candidate.id)) {
                        issuesTab(project: project, stores: stores)
                    }
                }
            }
            .defaultVisibility(.hidden, for: .tabBar)

            TabSection("Views") {
                ForEach(stores.saved.savedFilters) { filter in
                    Tab(filter.name, systemImage: "line.3.horizontal.decrease", value: AppTab.view(filter.id)) {
                        issuesTab(project: project, stores: stores)
                    }
                }
            }
            .defaultVisibility(.hidden, for: .tabBar)
        }
        .tabViewStyle(.sidebarAdaptable)
        .onChange(of: tab) { _, newTab in
            switch newTab {
            case .project(let id):
                handlePlace(.project(id), project: project, stores: stores)
            case .view(let id):
                handlePlace(.view(id), project: project, stores: stores)
            default:
                break
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environment(env)
                .themed()
        }
        .task { await env.projectListStore.loadIfNeeded() }
    }

    private func issuesTab(project: JiraProject, stores: ProjectStores) -> some View {
        NavigationSplitView {
            IssueListView(
                project: project,
                filterStore: stores.filter,
                savedFiltersStore: stores.saved,
                selection: $selectedIssue,
                onOpenSettings: { showingSettings = true },
                onVisibilityNote: { visibilityNote = $0 }
            )
            .id(project.id)
        } detail: {
            if let issue = selectedIssue {
                IssueDetailView(issue: issue, note: visibilityNote)
                    .id(issue.key)
            } else {
                EmptyInspectorView()
            }
        }
    }

    private var inboxTab: some View {
        NavigationSplitView {
            InboxListView(openedIssueKey: inboxIssue?.key, onOpen: { inboxIssue = $0 })
        } detail: {
            if let issue = inboxIssue {
                IssueDetailView(issue: issue)
                    .id(issue.key)
            } else {
                EmptyInspectorView()
            }
        }
    }
    #endif
}
