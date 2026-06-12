import SwiftUI
import BalmModels
import BalmDesignSystem

public struct MainShellView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var selectedIssue: JiraIssue?
    @State private var showingProjectChooser = false
    @State private var showingSettings = false
    @State private var navPath: [JiraIssue] = []

    public init() {}

    public var body: some View {
        Group {
            if let project = env.activeProjectStore.project {
                shell(for: project)
                    // Rebuild the whole shell (and its issue-list view model)
                    // when the active project changes, so switching projects in
                    // Settings loads fresh data instead of keeping the old one.
                    .id(project.id)
            } else {
                ProjectChooserView(isFirstRun: true)
            }
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
        .onChange(of: env.activeProjectStore.project) { _, _ in
            selectedIssue = nil
            navPath.removeAll()
        }
    }

    @ViewBuilder
    private func shell(for project: JiraProject) -> some View {
        #if os(macOS)
        macShell(project: project)
        #else
        adaptiveShell(project: project)
        #endif
    }

    // MARK: - Mac: list/board is main content, detail slides in from the right as an inspector

    #if os(macOS)
    private func macShell(project: JiraProject) -> some View {
        // Mac shell is just IssueListView itself — it owns the three-column
        // NavigationSplitView. Only the project chip toolbar lives here.
        // No project chip here — the project name is the nav title, and
        // changing it lives in Settings ▸ General ▸ Change Project (⌘,).
        IssueListView(project: project, selection: $selectedIssue)
    }
    #endif

    // MARK: - iOS / iPadOS: stack push for detail

    private func adaptiveShell(project: JiraProject) -> some View {
        NavigationStack(path: $navPath) {
            IssueListView(project: project, selection: $selectedIssue)
                .toolbar { settingsToolbar }
                .navigationDestination(for: JiraIssue.self) { issue in
                    IssueDetailView(issue: issue)
                }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environment(env)
                .themed()
        }
    }

    /// iOS settings entry point (macOS uses the ⌘, Settings scene).
    @ToolbarContentBuilder
    private var settingsToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Settings")
        }
    }

}

struct EmptyStateView: View {
    @Environment(\.balmTheme) private var theme
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: theme.spacing.s) {
            Text(title).font(theme.typography.headline).foregroundStyle(theme.palette.foreground)
            Text(message).font(theme.typography.callout).foregroundStyle(theme.palette.mutedForeground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(theme.spacing.xl)
    }
}
