import Foundation
import Observation
import UserNotifications
import BalmModels
import BalmAPI

/// Owns the Phase 1 in-app notification inbox: a poll loop that derives
/// `BalmNotification`s from `search/jql` (see `NotificationDiffer`), persisted
/// locally so the inbox survives relaunch. Lives on `AppEnvironment`.
@MainActor
@Observable
public final class InboxStore {
    public private(set) var items: [BalmNotification]
    public private(set) var syncState: NotificationSyncState
    public private(set) var lastSyncError: String?
    public private(set) var isSyncing = false
    /// Cross-device read-state sync document (see `InboxReadState`), pulled on
    /// every `syncNow()` and pushed (debounced) on read-state mutations.
    private var readState: InboxReadState
    /// Local-only exceptions to `readState`: ids the user explicitly marked
    /// unread on THIS device. The synced document's `readAllBeforeEpoch`
    /// watermark and grow-only `readIds` union can't express an unmark, so
    /// without this a pull would immediately re-read anything unmarked under
    /// a prior mark-all-read. Cleared per-id on read, wholesale on
    /// mark-all-read. Deliberately not synced (documented caveat).
    private var locallyUnread: Set<String>
    /// Set for the rest of the app session on a 401/403 from the read-state
    /// endpoints (OAuth token predates the new scopes, or they aren't enabled
    /// on the app in the developer console) — sync then stays local-only
    /// rather than retrying every poll. Surfaced in Settings.
    public private(set) var readSyncUnavailable = false

    /// Offered by Settings' "Check every" picker.
    public static let allowedPollIntervals = [60, 120, 300, 900]

    public var pollIntervalSeconds: Int {
        didSet {
            guard pollIntervalSeconds != oldValue else { return }
            UserDefaults.standard.set(pollIntervalSeconds, forKey: Self.pollIntervalKey)
            // The poll loop may be mid-`Task.sleep` computed from the old
            // interval (up to 15 min stale on backoff) — restart it so the
            // new cadence takes effect immediately. `start` preserves
            // `syncState` (same accountId, so its wipe-on-mismatch doesn't
            // fire) and its first sync doesn't re-trigger backfill labeling
            // since `syncState.cursor` is already set.
            if pollTask != nil, let accountId = myAccountId {
                start(accountId: accountId)
            }
        }
    }

    /// Lazily requests notification authorization the moment this flips on.
    public var systemNotificationsEnabled: Bool {
        didSet {
            guard systemNotificationsEnabled != oldValue else { return }
            UserDefaults.standard.set(systemNotificationsEnabled, forKey: Self.systemNotificationsKey)
            if systemNotificationsEnabled {
                requestNotificationAuthorizationIfNeeded()
            } else {
                updateAppBadge()
            }
        }
    }

    public var unreadCount: Int {
        items.reduce(0) { $1.isRead ? $0 : $0 + 1 }
    }

    private let api: JiraClient
    /// Injected rather than reading `NetworkMonitor` directly, so the poll
    /// loop is easy to drive in isolation.
    private let isOnline: () -> Bool
    /// Optional: background polls stay toast-free, but a user-initiated
    /// action (flipping the notifications toggle) surfaces a hint here.
    private let toaster: Toaster?
    private var myAccountId: String?
    private var pollTask: Task<Void, Never>?
    /// Debounced push of `readState` to the user property — cancel-and-replace
    /// so a burst of read-state mutations coalesces into one PUT.
    private var pushReadStateTask: Task<Void, Never>?

    private static let itemsKey = "inbox.items.v1"
    private static let syncStateKey = "inbox.syncState.v1"
    private static let readStateKey = "inbox.readState.v1"
    private static let locallyUnreadKey = "inbox.locallyUnread.v1"
    private static let pollIntervalKey = "inbox.pollIntervalSeconds"
    private static let systemNotificationsKey = "inbox.systemNotificationsEnabled"
    private static let itemsCap = 200
    private static let maxSyncPages = 5
    private static let pushReadStateDebounce = 3.0

    public init(api: JiraClient, isOnline: @escaping () -> Bool = { true }, toaster: Toaster? = nil) {
        self.api = api
        self.isOnline = isOnline
        self.toaster = toaster
        self.items = Self.loadItems()
        self.syncState = Self.loadSyncState()
        self.readState = Self.loadReadState()
        self.locallyUnread = Self.loadLocallyUnread()
        let storedInterval = UserDefaults.standard.integer(forKey: Self.pollIntervalKey)
        self.pollIntervalSeconds = Self.allowedPollIntervals.contains(storedInterval) ? storedInterval : 120
        self.systemNotificationsEnabled = UserDefaults.standard.bool(forKey: Self.systemNotificationsKey)
    }

    // MARK: - Lifecycle

    /// Begins polling for `accountId`. A different account than the one the
    /// persisted state was built for means a sign-in as someone else — wipe
    /// first so their notifications don't leak into the new session.
    public func start(accountId: String) {
        // Cancel the previous account's poll first so it can't resume past an
        // in-flight await and merge stale results into the state this wipes.
        // `syncNow` also re-checks `myAccountId` after every await as a
        // second line of defense — a task already past its last await when
        // cancel() lands wouldn't otherwise notice.
        pollTask?.cancel()
        pollTask = nil

        if let existing = syncState.accountId, existing != accountId {
            wipe()
        }
        syncState.accountId = accountId
        myAccountId = accountId
        // A fresh sign-in mints a new token that may now carry the
        // user-property scopes (Settings tells the user to re-authenticate
        // for exactly this reason) — give read-state sync another chance
        // rather than staying disabled until relaunch.
        readSyncUnavailable = false
        seedReadStateFromItems()

        pollTask = Task { [weak self] in
            await self?.pollLoop()
        }
    }

    public func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Sign-out: stop polling and forget everything, including on disk.
    public func stopAndReset() {
        stop()
        myAccountId = nil
        wipe()
    }

    private func wipe() {
        items = []
        syncState = NotificationSyncState()
        readState = InboxReadState()
        locallyUnread = []
        lastSyncError = nil
        // Cancel any in-flight debounced push — it would otherwise land after
        // this wipe and write the old account's read state back out.
        pushReadStateTask?.cancel()
        pushReadStateTask = nil
        UserDefaults.standard.removeObject(forKey: Self.itemsKey)
        UserDefaults.standard.removeObject(forKey: Self.syncStateKey)
        UserDefaults.standard.removeObject(forKey: Self.readStateKey)
        UserDefaults.standard.removeObject(forKey: Self.locallyUnreadKey)
        // The remote user property is left untouched — other devices still
        // signed into this account rely on it; only local state is cleared.
        // Previously delivered banners (issue keys, summaries, commenter
        // names from the old account) must not linger in the system
        // Notification Center past sign-out/account-switch.
        let center = UNUserNotificationCenter.current()
        center.removeAllDeliveredNotifications()
        center.removeAllPendingNotificationRequests()
        Task { try? await center.setBadgeCount(0) }
    }

    // MARK: - Poll loop

    /// Syncs immediately, then loops on `pollIntervalSeconds` (± jitter so
    /// many clients don't all hit the API on the same beat), doubling the
    /// wait on failure (capped at 15 minutes) and resetting it on success.
    private func pollLoop() async {
        await syncNow()
        var interval = Double(pollIntervalSeconds)
        while !Task.isCancelled {
            let jitter = interval * Double.random(in: -0.1...0.1)
            try? await Task.sleep(for: .seconds(max(1, interval + jitter)))
            if Task.isCancelled { return }

            await syncNow()
            interval = lastSyncError == nil ? Double(pollIntervalSeconds) : min(interval * 2, 900)
        }
    }

    // MARK: - Sync

    /// One sync pass: page `NotificationEndpoints.Search` for activity since
    /// the cursor, diff it, merge the results in, and persist. Safe to call
    /// directly (pull-to-refresh, foregrounding) alongside the poll loop —
    /// `isSyncing` guards against overlap.
    public func syncNow() async {
        guard !isSyncing, isOnline(), let accountId = myAccountId else { return }
        isSyncing = true
        defer { isSyncing = false }

        // Cross-device read-state pull happens first and is entirely
        // best-effort/silent (see `pullReadState`) — it must never set
        // `lastSyncError` or otherwise perturb the notification poll below.
        await pullReadState(accountId: accountId)
        guard !Task.isCancelled, myAccountId == accountId else { return }

        let wasFirstRun = syncState.cursor == nil
        let now = Date()
        let jql = NotificationSyncWindow.jql(cursor: syncState.cursor, now: now)

        do {
            var allIssues: [NotificationEndpoints.RawNotificationIssue] = []
            var nextToken: String?
            var pageCount = 0
            // Set when paging stops because `maxSyncPages` was hit while a
            // further page was still available — as opposed to genuinely
            // running out of pages (`isLast`/no token). Told to the differ so
            // it doesn't advance the cursor past the unfetched pages.
            var pageBudgetExhausted = false
            while true {
                pageCount += 1
                let page = try await api.send(NotificationEndpoints.Search(jql: jql, nextPageToken: nextToken))
                allIssues.append(contentsOf: page.issues)
                if page.isLast == true { break }
                guard let token = page.nextPageToken else { break }
                guard pageCount < Self.maxSyncPages else {
                    pageBudgetExhausted = true
                    break
                }
                nextToken = token
            }

            // The embedded `fields.comment` page is truncated (oldest-first,
            // page-capped) on any issue with more comments than that page —
            // fall back to a dedicated fetch of the newest comments for those.
            let supplementalComments = await fetchSupplementalComments(for: allIssues)

            // Re-check after every await above: an account switch (`start`)
            // may have wiped/reassigned state while this sync was in flight.
            guard !Task.isCancelled, myAccountId == accountId else { return }

            let diffed = NotificationDiffer.diff(
                issues: allIssues,
                state: syncState,
                myAccountId: accountId,
                now: now,
                supplementalComments: supplementalComments,
                pageBudgetExhausted: pageBudgetExhausted
            )
            var notifications = diffed.notifications
            // First run backfills history — it isn't "new" activity, so mark
            // it read and skip system notifications below.
            if wasFirstRun {
                notifications = notifications.map { var n = $0; n.isRead = true; return n }
            }

            merge(notifications)
            syncState = diffed.newState
            persistSyncState()
            lastSyncError = nil
            if wasFirstRun {
                // Backfill set `isRead` directly on the items, bypassing
                // `markRead` — fold those into the synced document too.
                seedReadStateFromItems()
            }

            if !wasFirstRun, !notifications.isEmpty {
                await postSystemNotifications(for: notifications)
            }
        } catch is CancellationError {
            // silent
        } catch let urlError as URLError where urlError.code == .cancelled {
            // silent — our own task cancellation (e.g. account switch) surfaces
            // as a cancelled URLSession task rather than `CancellationError`.
        } catch {
            // Same re-check as every other post-await mutation site: a sync
            // for the previous account must not write its stale error into
            // the account that replaced it mid-flight.
            guard !Task.isCancelled, myAccountId == accountId else { return }
            lastSyncError = error.localizedDescription
        }
    }

    // MARK: - Read-state sync

    /// Pulls the remote read-state property, unions it into the local
    /// document, applies any newly-read ids/epoch to `items` (read only ever
    /// moves forward here — a pull never flips a read item back to unread),
    /// and schedules a push if the merge picked up local ids the remote
    /// lacked (so a device that's ahead still converges the remote copy).
    ///
    /// Entirely best-effort and silent: a 401/403 permanently disables sync
    /// for the session (`readSyncUnavailable`); anything else just skips this
    /// round. Never touches `lastSyncError` — that's reserved for the
    /// user-visible notification poll.
    private func pullReadState(accountId: String) async {
        guard !readSyncUnavailable else { return }

        let remote: InboxReadState
        do {
            let envelope = try await api.send(NotificationEndpoints.GetReadState(accountId: accountId))
            remote = envelope.value
        } catch JiraError.http(let status, _) where status == 404 {
            remote = InboxReadState()
        } catch JiraError.http(let status, _) where status == 401 || status == 403 {
            guard !Task.isCancelled, myAccountId == accountId else { return }
            readSyncUnavailable = true
            return
        } catch {
            return
        }

        // Re-check after the await above: an account switch (`start`) may
        // have wiped/reassigned state while this GET was in flight.
        guard !Task.isCancelled, myAccountId == accountId else { return }

        let merged = InboxReadState.union(readState, remote)
        if merged != readState {
            readState = merged
            persistReadState()
        }

        var itemsChanged = false
        for index in items.indices where !items[index].isRead {
            // An explicit local unmark outranks the synced document — without
            // this, anything unmarked under a prior mark-all-read watermark
            // would flip straight back on the next pull.
            guard !locallyUnread.contains(items[index].id),
                  readState.isRead(id: items[index].id, date: items[index].date) else { continue }
            items[index].isRead = true
            itemsChanged = true
        }
        if itemsChanged { persistItems() }

        if merged != remote {
            schedulePushReadState()
        }
    }

    /// Folds any locally-read items the synced document doesn't know about
    /// into `readState`. Read state that predates the sync feature, or was
    /// applied directly by first-run backfill, would otherwise never
    /// propagate to other devices — the per-item `markRead` path is the only
    /// other writer of `readIds`.
    private func seedReadStateFromItems() {
        var changed = false
        for item in items where item.isRead && !readState.isRead(id: item.id, date: item.date) {
            readState.markRead(id: item.id)
            changed = true
        }
        if changed {
            persistReadState()
            schedulePushReadState()
        }
    }

    /// Debounced (cancel-and-replace) push of `readState` to the user
    /// property, so a burst of read/unread taps coalesces into one PUT.
    private func schedulePushReadState() {
        pushReadStateTask?.cancel()
        pushReadStateTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.pushReadStateDebounce))
            guard !Task.isCancelled else { return }
            await self?.pushReadStateNow()
        }
    }

    /// Pushes `readState` immediately, bypassing the debounce — for explicit
    /// bulk actions (`markAllRead`) where there's no burst to coalesce.
    private func pushReadStateImmediately() {
        pushReadStateTask?.cancel()
        pushReadStateTask = Task { [weak self] in
            await self?.pushReadStateNow()
        }
    }

    private func pushReadStateNow() async {
        guard !readSyncUnavailable, let accountId = myAccountId else { return }
        let stateToPush = readState
        do {
            try await api.sendVoid(NotificationEndpoints.PutReadState(accountId: accountId, state: stateToPush))
        } catch is CancellationError {
            // silent
        } catch let urlError as URLError where urlError.code == .cancelled {
            // silent — our own task cancellation (e.g. account switch).
        } catch JiraError.http(let status, _) where status == 401 || status == 403 {
            // Re-check after the await above: an account switch may have
            // reassigned state while this PUT was in flight.
            guard !Task.isCancelled, myAccountId == accountId else { return }
            readSyncUnavailable = true
        } catch {
            // silent — background push, best-effort, retried by the next
            // mutation or poll.
        }
    }

    /// Fetches the newest comments for issues whose embedded comment page was
    /// truncated, keyed by issue id. Best-effort: an issue that fails to fetch
    /// simply falls back to its (possibly truncated) embedded page.
    private func fetchSupplementalComments(
        for issues: [NotificationEndpoints.RawNotificationIssue]
    ) async -> [String: [NotificationEndpoints.RawNotificationIssue.Comment]] {
        let truncatedIds = Set(NotificationDiffer.truncatedCommentIssueIDs(in: issues))
        guard !truncatedIds.isEmpty else { return [:] }

        var result: [String: [NotificationEndpoints.RawNotificationIssue.Comment]] = [:]
        for issue in issues where truncatedIds.contains(issue.id) {
            guard let page = try? await api.send(NotificationEndpoints.RecentComments(issueKey: issue.key)) else {
                continue
            }
            result[issue.id] = page.comments
        }
        return result
    }

    /// Prepend newly-derived notifications (already deduped against `seenIds`
    /// by the differ), skipping anything somehow already present locally.
    private func merge(_ newOnes: [BalmNotification]) {
        guard !newOnes.isEmpty else { return }
        let existingIDs = Set(items.map(\.id))
        let toAdd = newOnes.filter { !existingIDs.contains($0.id) }
        guard !toAdd.isEmpty else { return }
        items = toAdd + items
        prune()
        persistItems()
    }

    /// Caps stored items at `itemsCap`, dropping the oldest already-read
    /// items first so unread activity is never silently lost to the cap.
    private func prune() {
        guard items.count > Self.itemsCap else { return }
        var excess = items.count - Self.itemsCap

        var dropIDs = Set<String>()
        let readOldestFirst = items.filter(\.isRead).sorted { $0.date < $1.date }
        for item in readOldestFirst where excess > 0 {
            dropIDs.insert(item.id)
            excess -= 1
        }
        if excess > 0 {
            let remainingOldestFirst = items
                .filter { !dropIDs.contains($0.id) }
                .sorted { $0.date < $1.date }
            for item in remainingOldestFirst where excess > 0 {
                dropIDs.insert(item.id)
                excess -= 1
            }
        }
        items.removeAll { dropIDs.contains($0.id) }
    }

    // MARK: - Read state (local mutation + synced document)

    public func markRead(_ id: String) {
        setRead(true, id: id)
    }

    public func markUnread(_ id: String) {
        setRead(false, id: id)
    }

    private func setRead(_ isRead: Bool, id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].isRead != isRead else { return }
        items[index].isRead = isRead
        if isRead {
            readState.markRead(id: id)
            if locallyUnread.remove(id) != nil { persistLocallyUnread() }
        } else {
            // The synced document can't express an unmark (grow-only union +
            // watermark), so record it in the local exception set too — that
            // keeps it unread on THIS device; other devices may still show it
            // read (see `InboxReadState.markUnread`'s doc comment). Accepted.
            readState.markUnread(id: id)
            locallyUnread.insert(id)
            persistLocallyUnread()
        }
        persistItems()
        persistReadState()
        schedulePushReadState()
    }

    public func markAllRead() {
        var changed = false
        for index in items.indices where !items[index].isRead {
            items[index].isRead = true
            changed = true
        }
        readState.markAllRead(asOf: Date())
        persistReadState()
        if !locallyUnread.isEmpty {
            locallyUnread.removeAll()
            persistLocallyUnread()
        }
        if changed { persistItems() }
        // Explicit bulk action — push right away rather than debouncing.
        pushReadStateImmediately()
    }

    // MARK: - System notifications

    /// Posts one local notification per new item, or a single summary
    /// notification when a sync brings in a flood (>5) so the user isn't
    /// spammed with a burst of banners.
    private func postSystemNotifications(for newItems: [BalmNotification]) async {
        guard systemNotificationsEnabled else { return }
        let center = UNUserNotificationCenter.current()
        guard await Self.systemNotificationsAreAuthorized(center: center) else { return }

        if newItems.count > 5 {
            let content = UNMutableNotificationContent()
            content.title = "Balm"
            content.body = "\(newItems.count) new updates in your inbox"
            try? await center.add(UNNotificationRequest(
                identifier: "inbox-summary-\(UUID().uuidString)", content: content, trigger: nil
            ))
            return
        }
        for item in newItems {
            let content = UNMutableNotificationContent()
            content.title = "\(item.issueKey) · \(Self.phrase(for: item.kind))"
            content.body = Self.body(for: item)
            content.threadIdentifier = item.issueKey
            try? await center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: nil))
        }
    }

    /// User-initiated (the Settings toggle), so a denied/unresolvable prompt
    /// flips the toggle back off and surfaces a toast rather than silently
    /// leaving it lying — a subsequent poll otherwise no-ops forever with the
    /// toggle still reading "on".
    private func requestNotificationAuthorizationIfNeeded() {
        Task { [weak self] in
            guard let self else { return }
            let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            guard !granted else {
                self.updateAppBadge()
                return
            }
            self.systemNotificationsEnabled = false
            self.toaster?.info("Notifications are disabled in System Settings")
        }
    }

    private static func phrase(for kind: BalmNotification.Kind) -> String {
        switch kind {
        case .assignedToYou: return "Assigned to you"
        case .statusChanged(_, let to): return to.map { "Moved to \($0)" } ?? "Status changed"
        case .commented: return "New comment"
        case .mentioned: return "Mentioned you"
        case .fieldUpdated(let field): return "\(field) updated"
        }
    }

    private static func body(for item: BalmNotification) -> String {
        switch item.kind {
        case .commented(let excerpt), .mentioned(let excerpt):
            return excerpt ?? item.issueSummary
        default:
            return item.issueSummary
        }
    }

    // MARK: - Persistence

    private func persistItems() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: Self.itemsKey)
        // Every read-state or item mutation funnels through here, so it's
        // the one hook that keeps the app-icon badge in step.
        updateAppBadge()
    }

    /// Mirrors `unreadCount` onto the app icon (iOS home screen / macOS
    /// dock). Gated on the same toggle as banners; a denied `.badge`
    /// authorization makes the call fail silently, which is fine.
    private func updateAppBadge() {
        let count = systemNotificationsEnabled ? unreadCount : 0
        Task {
            try? await UNUserNotificationCenter.current().setBadgeCount(count)
        }
    }

    private nonisolated static func systemNotificationsAreAuthorized(center: UNUserNotificationCenter) async -> Bool {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                let status = settings.authorizationStatus
                continuation.resume(returning: status == .authorized || status == .provisional)
            }
        }
    }

    private static func loadItems() -> [BalmNotification] {
        guard let data = UserDefaults.standard.data(forKey: itemsKey),
              let decoded = try? JSONDecoder().decode([BalmNotification].self, from: data)
        else { return [] }
        return decoded
    }

    private func persistSyncState() {
        guard let data = try? JSONEncoder().encode(syncState) else { return }
        UserDefaults.standard.set(data, forKey: Self.syncStateKey)
    }

    private static func loadSyncState() -> NotificationSyncState {
        guard let data = UserDefaults.standard.data(forKey: syncStateKey),
              let decoded = try? JSONDecoder().decode(NotificationSyncState.self, from: data)
        else { return NotificationSyncState() }
        return decoded
    }

    private func persistReadState() {
        guard let data = try? JSONEncoder().encode(readState) else { return }
        UserDefaults.standard.set(data, forKey: Self.readStateKey)
    }

    private static func loadReadState() -> InboxReadState {
        guard let data = UserDefaults.standard.data(forKey: readStateKey),
              let decoded = try? JSONDecoder().decode(InboxReadState.self, from: data)
        else { return InboxReadState() }
        return decoded
    }

    private func persistLocallyUnread() {
        guard let data = try? JSONEncoder().encode(locallyUnread) else { return }
        UserDefaults.standard.set(data, forKey: Self.locallyUnreadKey)
    }

    private static func loadLocallyUnread() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: locallyUnreadKey),
              let decoded = try? JSONDecoder().decode(Set<String>.self, from: data)
        else { return [] }
        return decoded
    }
}
