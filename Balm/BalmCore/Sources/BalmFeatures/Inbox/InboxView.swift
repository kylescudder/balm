import SwiftUI
import BalmModels
import BalmAPI
import BalmDesignSystem

/// The notification inbox as a place, not a sheet. Lives in the Mac content
/// column and the iOS Inbox tab; selecting a row resolves the full issue and
/// hands it to `onOpen`, which the shell shows in the inspector or the split
/// view's detail column. The list stays put.
public struct InboxListView: View {
    @Environment(AppEnvironment.self) private var env

    private let onOpen: (JiraIssue) -> Void

    // Keyed on id, not the whole value: `BalmNotification`'s `Hashable`
    // includes `isRead`, so a value-keyed selection stops matching its row's
    // `.tag` the instant `activate` marks it read.
    @State private var selection: BalmNotification.ID?
    /// Cancel-and-replace: only one activation in flight at a time, so a slow
    /// earlier fetch can't open a stale issue and arrow-keying through rows
    /// doesn't fire one network request per keypress.
    @State private var activateTask: Task<Void, Never>?
    @State private var isOpening = false
    @State private var showUnreadOnly = false

    public init(onOpen: @escaping (JiraIssue) -> Void) {
        self.onOpen = onOpen
    }

    public var body: some View {
        Group {
            if visibleItems.isEmpty {
                if showUnreadOnly && !env.inboxStore.items.isEmpty {
                    ContentUnavailableView("No unread notifications", systemImage: "tray")
                } else {
                    ContentUnavailableView {
                        Label("You're all caught up", systemImage: "tray")
                    } description: {
                        Text("Activity on issues you're assigned, reporting or watching shows up here.")
                    }
                }
            } else {
                listBody
            }
        }
        .navigationTitle("Inbox")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { toolbarContent }
        .safeAreaInset(edge: .bottom) {
            if let error = env.inboxStore.lastSyncError {
                Text("Couldn't refresh: \(error)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.bar)
            }
        }
        .onChange(of: selection) { _, newValue in
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
                            Button("Mark as unread") { env.inboxStore.markUnread(notification.id) }
                        } else {
                            Button("Mark as read") { env.inboxStore.markRead(notification.id) }
                        }
                    }
            }
        }
        #if os(macOS)
        .listStyle(.inset)
        #else
        .listStyle(.insetGrouped)
        #endif
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
        ToolbarItem {
            Button {
                Task { await env.inboxStore.syncNow() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(env.inboxStore.isSyncing)
            .help("Refresh (⌘R)")
        }
        #endif
        ToolbarItem {
            Button {
                env.inboxStore.markAllRead()
            } label: {
                Label("Mark all read", systemImage: "checkmark.circle")
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .help("Mark all read (⇧⌘R)")
            .disabled(env.inboxStore.unreadCount == 0)
        }
    }

    /// Resolves the notification to a full `JiraIssue` (the inbox only carries
    /// a key/summary), then — only if this is still the current selection and
    /// this task wasn't superseded — marks it read and hands the issue to the
    /// shell. A row merely traversed by arrow keys (and superseded before its
    /// fetch lands) is never marked read.
    private func activate(_ notification: BalmNotification) async {
        let issue = await fetchIssue(key: notification.issueKey)
        guard !Task.isCancelled, selection == notification.id else { return }
        isOpening = false
        guard let issue else { return }
        env.inboxStore.markRead(notification.id)
        onOpen(issue)
    }

    private func fetchIssue(key: String) async -> JiraIssue? {
        do {
            let instanceField = await env.api.resolveInstanceFieldID()
            let raw = try await env.api.send(IssueEndpoints.GetDetail(issueKey: key))
            return IssueDetailMapper.decode(raw, instanceFieldID: instanceField).0
        } catch {
            env.toaster.report(error, "Couldn't open \(key)")
            return nil
        }
    }
}
