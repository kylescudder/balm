import SwiftUI
import BalmModels
import BalmAPI
import BalmDesignSystem

/// The notification inbox, presented as a native modal sheet by
/// `MainShellView`. Reads `env.inboxStore` directly (it lives on
/// `AppEnvironment`, so there's no placeholder-VM reconnect dance needed).
/// Opening a notification resolves the full issue, dismisses the sheet, and
/// hands the issue to `onOpen`, which presents it on the shell's own surface
/// (macOS inspector / iOS stack push) — detail is never shown inside the
/// sheet itself.
public struct InboxView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.balmTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    /// Presents the resolved issue once the sheet has been dismissed.
    private let onOpen: (JiraIssue) -> Void

    // Keyed on id, not the whole value: `BalmNotification`'s `Hashable`
    // includes `isRead`, so a value-keyed selection stops matching its row's
    // `.tag` the instant `activate` marks it read.
    @State private var selection: BalmNotification.ID?
    /// Cancel-and-replace: only one activation in flight at a time, so a slow
    /// earlier fetch can't dismiss the sheet with a stale issue and
    /// arrow-keying through rows doesn't fire one network request per
    /// keypress.
    @State private var activateTask: Task<Void, Never>?
    @State private var isOpening = false
    @State private var showUnreadOnly = false

    public init(onOpen: @escaping (JiraIssue) -> Void) {
        self.onOpen = onOpen
    }

    public var body: some View {
        NavigationStack {
            mainContent
                .toolbar { toolbarContent }
        }
        #if os(macOS)
        // macOS sheets size to their content; give the inbox a full-view
        // footprint (mirrors ProjectChooserView's explicit sheet frame).
        .frame(minWidth: 640, idealWidth: 760, maxWidth: 900, minHeight: 520, idealHeight: 680, maxHeight: .infinity)
        #endif
    }

    @ViewBuilder
    private var mainContent: some View {
        Group {
            if visibleItems.isEmpty {
                if showUnreadOnly && !env.inboxStore.items.isEmpty {
                    ContentUnavailableView("No unread notifications", systemImage: "tray")
                } else {
                    ContentUnavailableView("You're all caught up", systemImage: "tray")
                }
            } else {
                listBody
            }
        }
        .navigationTitle(env.inboxStore.unreadCount > 0 ? "Inbox (\(env.inboxStore.unreadCount))" : "Inbox")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .safeAreaInset(edge: .bottom) {
            if let error = env.inboxStore.lastSyncError {
                Text("Couldn't refresh: \(error)")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.palette.mutedForeground)
                    .padding(.horizontal, theme.spacing.m)
                    .padding(.vertical, theme.spacing.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial)
            }
        }
        .onChange(of: selection) { _, newValue in
            // Cancel any in-flight activation first: a slow earlier fetch
            // must not win over a faster later one, and arrow-keying through
            // rows should fire at most one request, not one per keypress
            // traversed.
            activateTask?.cancel()
            guard let newValue, let notification = env.inboxStore.items.first(where: { $0.id == newValue }) else {
                isOpening = false
                return
            }
            isOpening = true
            activateTask = Task {
                await activate(notification)
            }
        }
    }

    private var visibleItems: [BalmNotification] {
        showUnreadOnly ? env.inboxStore.items.filter { !$0.isRead } : env.inboxStore.items
    }

    private var listBody: some View {
        List(selection: $selection) {
            ForEach(visibleItems) { notification in
                InboxRowView(notification: notification)
                    .tag(notification.id)
                    .contextMenu {
                        if notification.isRead {
                            Button("Mark as Unread") { env.inboxStore.markUnread(notification.id) }
                        } else {
                            Button("Mark as Read") { env.inboxStore.markRead(notification.id) }
                        }
                    }
            }
        }
        .refreshable { await env.inboxStore.syncNow() }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Filter", selection: $showUnreadOnly) {
                Text("All").tag(false)
                Text("Unread").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 160)
            .help("Filter notifications")
        }
        ToolbarItem {
            if env.inboxStore.isSyncing || isOpening {
                ProgressView().controlSize(.small)
            }
        }
        #if os(macOS)
        // iOS gets `.refreshable` (pull-to-refresh); macOS has no such
        // gesture, so it needs an explicit toolbar affordance — mirrors
        // `IssueListView.macToolbar`'s Refresh button. While the sheet is the
        // key window its ⌘R wins over the menu's, so the Issues section
        // underneath doesn't also refresh.
        ToolbarItem {
            Button {
                Task { await env.inboxStore.syncNow() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(env.inboxStore.isSyncing)
            .help("Refresh (⌘R)")
        }
        #endif
        ToolbarItem {
            Button {
                env.inboxStore.markAllRead()
            } label: {
                Label("Mark All Read", systemImage: "checkmark.circle")
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .help("Mark all read (⇧⌘R)")
            .disabled(env.inboxStore.unreadCount == 0)
        }
        ToolbarItem(placement: .cancellationAction) {
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
    }

    /// Resolves the notification to a full `JiraIssue` (the inbox only
    /// carries a key/summary), then — only if this is still the current
    /// selection and this task wasn't superseded — marks it read, dismisses
    /// the sheet, and hands the issue to the shell. Marking read only happens
    /// here, after a successful, still-selected fetch, so a row merely
    /// traversed by arrow keys (and superseded before its fetch lands) is
    /// never marked read.
    private func activate(_ notification: BalmNotification) async {
        let issue = await fetchIssue(key: notification.issueKey)
        guard !Task.isCancelled, selection == notification.id else { return }
        isOpening = false
        // Reset either way so re-selecting the same row later re-fires
        // `onChange(of: selection)` — otherwise the value is unchanged and
        // the row goes dead until a different row is selected first.
        selection = nil
        guard let issue else { return }
        env.inboxStore.markRead(notification.id)
        dismiss()
        onOpen(issue)
    }

    private func fetchIssue(key: String) async -> JiraIssue? {
        do {
            let instanceField = await env.api.resolveInstanceFieldID()
            let raw = try await env.api.send(IssueEndpoints.GetDetail(issueKey: key))
            return IssueDetailMapper.decode(raw, instanceFieldID: instanceField).0
        } catch {
            env.toaster.error("Couldn't open \(key): \(error.localizedDescription)")
            return nil
        }
    }
}
