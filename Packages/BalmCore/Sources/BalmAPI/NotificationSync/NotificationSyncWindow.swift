import Foundation

/// Computes the JQL search window for a notification poll. Pure — derives
/// everything from `cursor`/`now`, no `Date()` calls, fully unit-testable.
///
/// Relative-minutes JQL (`updated >= -Nm`, unquoted) deliberately avoids JQL's
/// timezone ambiguity around absolute dates.
public enum NotificationSyncWindow {
    /// First run (no cursor yet): backfill the last 24 hours.
    public static let backfillMinutes = 1440
    /// Added to the computed window so activity landing right at the cursor
    /// boundary isn't missed by JQL's minute-granularity relative dates.
    /// `NotificationDiffer` uses the same constant as its notification cutoff.
    public static let overlapMinutes = 2
    public static let minMinutes = 3
    public static let maxMinutes = 20160 // 14 days

    /// Minutes to look back from `now`, clamped to `[minMinutes, maxMinutes]`.
    public static func minutes(cursor: Date?, now: Date) -> Int {
        guard let cursor else { return backfillMinutes }
        let elapsedMinutes = Int((now.timeIntervalSince(cursor) / 60).rounded(.up))
        let windowed = elapsedMinutes + overlapMinutes
        return min(max(windowed, minMinutes), maxMinutes)
    }

    /// The JQL used to poll for notification-worthy activity:
    /// `(assignee = currentUser() OR reporter = currentUser() OR watcher = currentUser())
    ///  AND updated >= -<N>m ORDER BY updated DESC`.
    public static func jql(cursor: Date?, now: Date) -> String {
        let n = minutes(cursor: cursor, now: now)
        return "(assignee = currentUser() OR reporter = currentUser() OR watcher = currentUser())"
            + " AND updated >= -\(n)m ORDER BY updated DESC"
    }
}
