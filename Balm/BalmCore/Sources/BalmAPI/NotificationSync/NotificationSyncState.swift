import Foundation

/// Local cursor + dedupe bookkeeping for the notification poll. Persisted as
/// JSON by `InboxStore` so notifications aren't re-derived across launches.
public struct NotificationSyncState: Codable, Sendable, Equatable {
    /// The latest `updated` timestamp seen across any polled issue. `nil` means
    /// no sync has run yet — the next poll performs a backfill.
    public var cursor: Date?
    /// The signed-in user's accountId this state was built for; a mismatch
    /// (account switch) tells `InboxStore` to wipe and start fresh.
    public var accountId: String?
    /// Bounded FIFO of dedupe ids already surfaced as notifications.
    public var seenIds: [String]

    /// Cap on `seenIds` — oldest ids are dropped first once exceeded.
    public static let seenIdsCap = 500

    public init(cursor: Date? = nil, accountId: String? = nil, seenIds: [String] = []) {
        self.cursor = cursor
        self.accountId = accountId
        self.seenIds = seenIds
    }

    /// Appends newly surfaced dedupe ids, trimming the oldest entries once the
    /// FIFO exceeds `seenIdsCap`.
    public mutating func recordSeen(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        seenIds.append(contentsOf: ids)
        if seenIds.count > Self.seenIdsCap {
            seenIds.removeFirst(seenIds.count - Self.seenIdsCap)
        }
    }
}
