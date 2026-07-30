import Foundation

/// Conflict-free read-state document synced across devices via a Jira user
/// property (`NotificationEndpoints.readStatePropertyKey` — see
/// `NotificationEndpoints.GetReadState`/`PutReadState`). Every device pulls,
/// merges with `union`, and pushes back, so no device's "read" marks are ever
/// lost to a last-write-wins overwrite from another device.
///
/// Epoch-second `Double`s are used instead of `Date` throughout: `JSONDecoder.jira`
/// expects Jira's string date formats and `JiraEndpointBuilder`'s plain
/// `JSONEncoder` writes `Date` as a numeric timestamp anyway — plain `Double`
/// sidesteps both codec mismatches entirely, since this document round-trips
/// through a user property, not a Jira date field.
public struct InboxReadState: Codable, Sendable, Equatable {
    /// FIFO of read notification ids, oldest first; capped at `readIdsCap`.
    public var readIds: [String]
    /// Epoch seconds. Any item dated at or before this is considered read,
    /// independent of `readIds` — set by "mark all read".
    public var readAllBeforeEpoch: Double?
    /// Informational only — last time this document was mutated locally.
    public var updatedAtEpoch: Double?

    /// Cap on `readIds` — oldest ids are dropped first once exceeded. Keeps
    /// the synced property comfortably under Jira's 32 KB per-property limit
    /// (~15 KB worst case at this cap).
    public static let readIdsCap = 500

    public init(
        readIds: [String] = [],
        readAllBeforeEpoch: Double? = nil,
        updatedAtEpoch: Double? = nil
    ) {
        self.readIds = readIds
        self.readAllBeforeEpoch = readAllBeforeEpoch
        self.updatedAtEpoch = updatedAtEpoch
    }

    /// Merges two documents from possibly-different devices: the union of
    /// `readIds` (`a`'s order preserved, then `b`'s novel ids appended,
    /// re-capped dropping the oldest), the max `readAllBeforeEpoch`, and the
    /// max `updatedAtEpoch`. Commutative in effect (same resulting set
    /// regardless of argument order) and idempotent (`union(x, x) == x`).
    public static func union(_ a: InboxReadState, _ b: InboxReadState) -> InboxReadState {
        var mergedIds = a.readIds
        let existing = Set(a.readIds)
        for id in b.readIds where !existing.contains(id) {
            mergedIds.append(id)
        }
        if mergedIds.count > readIdsCap {
            mergedIds.removeFirst(mergedIds.count - readIdsCap)
        }
        return InboxReadState(
            readIds: mergedIds,
            readAllBeforeEpoch: maxOptional(a.readAllBeforeEpoch, b.readAllBeforeEpoch),
            updatedAtEpoch: maxOptional(a.updatedAtEpoch, b.updatedAtEpoch)
        )
    }

    private static func maxOptional(_ a: Double?, _ b: Double?) -> Double? {
        switch (a, b) {
        case (nil, nil): return nil
        case (let a?, nil): return a
        case (nil, let b?): return b
        case (let a?, let b?): return max(a, b)
        }
    }

    /// Whether `id` (dated `date`) should be considered read: present in
    /// `readIds`, or dated at/before `readAllBeforeEpoch`.
    public func isRead(id: String, date: Date) -> Bool {
        if readIds.contains(id) { return true }
        if let epoch = readAllBeforeEpoch, date.timeIntervalSince1970 <= epoch { return true }
        return false
    }

    public mutating func markRead(id: String) {
        guard !readIds.contains(id) else { return }
        readIds.append(id)
        recap()
        bumpUpdated()
    }

    /// Removes `id` from `readIds`. Note the caveat this doesn't engineer
    /// around: if `id`'s date falls at/before `readAllBeforeEpoch`,
    /// `isRead(id:date:)` still reports it read via the epoch — and even
    /// when it doesn't, another device that hasn't pulled this unmark yet may
    /// push its own (stale) doc still containing `id`, which `union` will
    /// re-add. There's no tombstone here to prevent that; a device converges
    /// back to read on its next pull. Accepted as a rare, self-correcting race
    /// rather than adding removal-tombstone bookkeeping.
    public mutating func markUnread(id: String) {
        guard let index = readIds.firstIndex(of: id) else { return }
        readIds.remove(at: index)
        bumpUpdated()
    }

    /// Marks everything at/before `asOf` read. `readIds` is cleared rather
    /// than pruned: ids don't carry dates, but the new epoch already covers
    /// everything at or before `asOf`, and anything newer was never read to
    /// begin with — so there's nothing left for `readIds` to usefully hold.
    public mutating func markAllRead(asOf: Date) {
        let epoch = asOf.timeIntervalSince1970
        readAllBeforeEpoch = readAllBeforeEpoch.map { max($0, epoch) } ?? epoch
        readIds = []
        bumpUpdated()
    }

    private mutating func recap() {
        if readIds.count > Self.readIdsCap {
            readIds.removeFirst(readIds.count - Self.readIdsCap)
        }
    }

    private mutating func bumpUpdated() {
        updatedAtEpoch = Date().timeIntervalSince1970
    }
}
