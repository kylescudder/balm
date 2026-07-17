import SwiftUI
import BalmModels
import BalmDesignSystem

public struct MainShellView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.balmTheme) private var theme
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedIssue: JiraIssue?
    @State private var showingProjectChooser = false
    @State private var showingSettings = false
    @State private var showingInbox = false
    @State private var navPath: [JiraIssue] = []

    public init() {}

    public var body: some View {
        Group {
            if let project = env.activeProjectStore.project {
                shell(for: project)
            } else {
                ProjectChooserView(isFirstRun: true)
            }
        }
        .sheet(isPresented: $showingProjectChooser) {
            ProjectChooserView(isFirstRun: false)
                .environment(env)
                .themed()
        }
        // The Inbox is account-scoped and transient, so it pops out as a
        // native sheet over whichever project is active. Opening a
        // notification dismisses the sheet and presents the issue on the
        // shell's own surface via `open(fromInbox:)`.
        .sheet(isPresented: $showingInbox) {
            InboxView(onOpen: open(fromInbox:))
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
            showingInbox = true
        }
        .onChange(of: env.activeProjectStore.project) { _, _ in
            selectedIssue = nil
            navPath.removeAll()
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

    /// Presents an issue chosen in the Inbox sheet the same way the rest of
    /// the app presents detail: the macOS inspector / the iOS stack push.
    private func open(fromInbox issue: JiraIssue) {
        #if os(macOS)
        selectedIssue = issue
        #else
        navPath.append(issue)
        #endif
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
        IssueListView(project: project, selection: $selectedIssue)
            // Rebuild Issues (and its view model) when the active project
            // changes; the Inbox sheet isn't project-scoped so it hangs off
            // the shell, outside this identity.
            .id(project.id)
            .toolbar { inboxToolbar }
            .background { inboxShortcutSink }
    }

    /// Invisible button owning the bare-`I` inbox shortcut, mirroring
    /// `IssueListView.viewShortcutSink` — single keys don't fire while a text
    /// field (the issue search bar) has focus. While the sheet is up it isn't
    /// in the key window, so `I` only opens; Esc/Done closes.
    private var inboxShortcutSink: some View {
        Button("Inbox") {
            showingInbox = true
        }
        .keyboardShortcut("i", modifiers: [])
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
    #endif

    // MARK: - iOS / iPadOS: single stack, detail is a push, inbox is a sheet

    private func adaptiveShell(project: JiraProject) -> some View {
        NavigationStack(path: $navPath) {
            IssueListView(project: project, selection: $selectedIssue)
                .toolbar {
                    settingsToolbar
                    inboxToolbar
                }
                .navigationDestination(for: JiraIssue.self) { issue in
                    IssueDetailView(issue: issue)
                }
        }
        .environment(\.openIssue, OpenIssueAction { navPath.append($0) })
        // Rebuild Issues only when the project changes.
        .id(project.id)
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

    @ToolbarContentBuilder
    private var inboxToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                showingInbox = true
            } label: {
                // Unread state changes the glyph itself (tray.full) as well
                // as showing the dot: iOS 26's glass-capsule toolbar buttons
                // clip decoration drawn outside the icon bounds, so the dot
                // stays inside them and the glyph carries the state even if
                // a button style crops corners.
                Image(systemName: env.inboxStore.unreadCount > 0 ? "tray.full" : "tray")
                    .overlay(alignment: .topTrailing) {
                        if env.inboxStore.unreadCount > 0 {
                            Circle()
                                .fill(theme.palette.destructive)
                                .frame(width: 7, height: 7)
                                .allowsHitTesting(false)
                        }
                    }
                    .accessibilityLabel(
                        env.inboxStore.unreadCount > 0
                            ? "Inbox, \(env.inboxStore.unreadCount) unread"
                            : "Inbox"
                    )
            }
            .help(inboxHelp)
        }
    }

    private var inboxHelp: String {
        #if os(macOS)
        return "Inbox — I"
        #else
        return "Inbox"
        #endif
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
