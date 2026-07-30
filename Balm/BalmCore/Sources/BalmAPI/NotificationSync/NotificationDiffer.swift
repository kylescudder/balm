import Foundation
import BalmModels

/// Derives typed `BalmNotification`s from a poll's raw issues, mirroring
/// Jira's own bell-notification rules. Pure — no side effects; the caller
/// supplies `now` (mirroring `NotificationSyncWindow`) rather than this type
/// calling `Date()` itself, so it's fully unit-testable.
public enum NotificationDiffer {
    /// Diffs a page of polled issues against the local sync state.
    ///
    /// For each issue, every changelog history and comment newer than
    /// `state.cursor` (minus the sync window's overlap) and not already in
    /// `state.seenIds` becomes at most one notification. Activity authored by
    /// `myAccountId` is suppressed. The returned state's cursor advances to the
    /// max `updated` across `issues` (never regressing) and `seenIds` gains the
    /// newly surfaced dedupe ids.
    ///
    /// - Parameters:
    ///   - now: Used only to floor the first-run backfill window (see below).
    ///     Callers pass the same instant used to build the poll's JQL window
    ///     (`NotificationSyncWindow.jql(cursor:now:)`) so the two stay consistent.
    ///   - supplementalComments: Full/recent comment lists for issues whose
    ///     embedded `fields.comment` page was truncated (see
    ///     `truncatedCommentIssueIDs(in:)`), keyed by issue id. When present for
    ///     an issue, this replaces its embedded comments entirely.
    ///   - pageBudgetExhausted: Pass `true` when the caller stopped paging
    ///     because it hit its page cap while a further page was still
    ///     available (as opposed to genuinely running out of pages). `issues`
    ///     is ordered newest-`updated`-first, so the unfetched pages are
    ///     *older* than the last issue fetched but may still be newer than the
    ///     previous cursor — advancing all the way to `issues`' max `updated`
    ///     would permanently skip them. Instead the cursor only advances to
    ///     the *minimum* `updated` across the fetched issues (never regressing
    ///     below its previous value); the next poll re-covers the gap and
    ///     `seenIds` dedupes the overlap.
    public static func diff(
        issues: [NotificationEndpoints.RawNotificationIssue],
        state: NotificationSyncState,
        myAccountId: String,
        now: Date = Date(),
        supplementalComments: [String: [NotificationEndpoints.RawNotificationIssue.Comment]] = [:],
        pageBudgetExhausted: Bool = false
    ) -> (notifications: [BalmNotification], newState: NotificationSyncState) {
        // Events at/after this instant are candidates; `seenIds` does the final
        // dedup within the overlap. `nil` cursor (first run) floors at the
        // backfill window's start rather than accepting everything — otherwise
        // a "24-hour backfill" would actually backfill each issue's full history.
        let cursorFloor = state.cursor.map { $0.addingTimeInterval(-Double(NotificationSyncWindow.overlapMinutes * 60)) }
            ?? now.addingTimeInterval(-Double(NotificationSyncWindow.backfillMinutes * 60))

        var seen = Set(state.seenIds)
        var newIds: [String] = []
        var notifications: [BalmNotification] = []
        var maxUpdated = state.cursor
        /// The oldest `updated` across the fetched issues — only consulted
        /// when `pageBudgetExhausted`.
        var minUpdated: Date?

        for issue in issues {
            let issueId = issue.id
            let issueKey = issue.key
            let summary = issue.fields.summary

            for history in issue.changelog?.histories ?? [] {
                guard let created = history.created, isCandidate(created, floor: cursorFloor) else { continue }
                guard history.author.accountId != myAccountId else { continue }
                let dedupeId = "\(issueId).changelog.\(history.id)"
                guard !seen.contains(dedupeId), let kind = kind(for: history.items, myAccountId: myAccountId) else { continue }

                notifications.append(BalmNotification(
                    id: dedupeId,
                    kind: kind,
                    issueKey: issueKey,
                    issueSummary: summary,
                    actorDisplayName: history.author.displayName,
                    date: created
                ))
                seen.insert(dedupeId)
                newIds.append(dedupeId)
            }

            let comments = supplementalComments[issueId] ?? issue.fields.comment?.comments ?? []
            for comment in comments {
                guard let created = comment.created, isCandidate(created, floor: cursorFloor) else { continue }
                guard comment.author.accountId != myAccountId else { continue }
                let dedupeId = "\(issueId).comment.\(comment.id)"
                guard !seen.contains(dedupeId) else { continue }

                let mentioned = comment.body.map { containsMention(of: myAccountId, in: $0.rawJSON) } ?? false
                notifications.append(BalmNotification(
                    id: dedupeId,
                    kind: mentioned ? .mentioned(excerpt: nil) : .commented(excerpt: nil),
                    issueKey: issueKey,
                    issueSummary: summary,
                    actorDisplayName: comment.author.displayName,
                    date: created
                ))
                seen.insert(dedupeId)
                newIds.append(dedupeId)
            }

            if let updated = issue.fields.updated {
                if maxUpdated == nil || updated > maxUpdated! {
                    maxUpdated = updated
                }
                if minUpdated == nil || updated < minUpdated! {
                    minUpdated = updated
                }
            }
        }

        notifications.sort { $0.date > $1.date }

        var newState = state
        if pageBudgetExhausted, let minUpdated {
            // Never regress below the previous cursor even though we're
            // advancing more conservatively than `maxUpdated` would.
            newState.cursor = state.cursor.map { max($0, minUpdated) } ?? minUpdated
        } else {
            newState.cursor = maxUpdated
        }
        newState.recordSeen(newIds)

        return (notifications, newState)
    }

    private static func isCandidate(_ date: Date, floor: Date) -> Bool {
        date > floor
    }

    /// Issue ids whose embedded comment page is truncated — the poll's
    /// `fields.comment` expansion returns only the first page (oldest-first),
    /// so an issue with more comments than that page holds `total` comments
    /// exceeding the count actually embedded. Callers should re-fetch the
    /// full/recent comment list for these ids (e.g. `GET /issue/{key}/comment
    /// ?orderBy=-created`) and pass the result back in as `supplementalComments`
    /// — otherwise new comments on the busiest issues are silently dropped.
    public static func truncatedCommentIssueIDs(
        in issues: [NotificationEndpoints.RawNotificationIssue]
    ) -> [String] {
        issues.compactMap { issue in
            guard let page = issue.fields.comment, let total = page.total, total > page.comments.count else {
                return nil
            }
            return issue.id
        }
    }

    /// One notification per history entry, not per item: an assignment to
    /// `myAccountId` wins outright, then a status transition, else a generic
    /// field-updated fallback naming the first item's field.
    private static func kind(
        for items: [NotificationEndpoints.RawNotificationIssue.Item],
        myAccountId: String
    ) -> BalmNotification.Kind? {
        guard let first = items.first else { return nil }
        if let assigned = items.first(where: { $0.field == "assignee" }), assigned.to == myAccountId {
            return .assignedToYou
        }
        if let status = items.first(where: { $0.field == "status" }) {
            return .statusChanged(from: status.fromString, to: status.toString)
        }
        return .fieldUpdated(field: first.field)
    }

    /// Simple containment of the accountId string inside the raw ADF body JSON
    /// — a mention node carries it verbatim as its `attrs.id`.
    private static func containsMention(of accountId: String, in bodyJSON: Data) -> Bool {
        guard !bodyJSON.isEmpty, !accountId.isEmpty,
              let text = String(data: bodyJSON, encoding: .utf8) else { return false }
        return text.contains(accountId)
    }
}
