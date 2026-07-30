import XCTest
import BalmModels
@testable import BalmAPI

final class NotificationDifferTests: XCTestCase {
    private let me = "acc-me"

    private func date(_ iso: String) -> Date {
        JiraDate.parse(iso)
    }

    /// Decodes a `{"issues": [...]}` wrapper the same way a poll response would.
    private func issues(_ json: String) throws -> [NotificationEndpoints.RawNotificationIssue] {
        try JSONDecoder.jira.decode(
            NotificationEndpoints.Search.PagedResponse.self,
            from: Data(#"{"issues": \#(json), "nextPageToken": null, "isLast": true}"#.utf8)
        ).issues
    }

    // MARK: - Changelog derivation

    func testAssignedToYouDetectedViaRawTo() throws {
        let raw = try issues(#"""
        [{
          "id": "10001", "key": "ABC-1",
          "fields": { "summary": "Fix the thing", "created": "2026-07-01T09:00:00.000+0000", "updated": "2026-07-16T10:00:00.000+0000" },
          "changelog": { "histories": [{
            "id": "8001", "author": { "accountId": "acc-other", "displayName": "Other Person" },
            "created": "2026-07-16T09:58:00.000+0000",
            "items": [{ "field": "assignee", "from": null, "to": "acc-me", "fromString": null, "toString": "Me" }]
          }] }
        }]
        """#)

        let state = NotificationSyncState(cursor: date("2026-07-16T09:00:00.000+0000"), accountId: me)
        let (notifications, _) = NotificationDiffer.diff(issues: raw, state: state, myAccountId: me)

        XCTAssertEqual(notifications.count, 1)
        let n = try XCTUnwrap(notifications.first)
        XCTAssertEqual(n.id, "10001.changelog.8001")
        XCTAssertEqual(n.kind, .assignedToYou)
        XCTAssertEqual(n.issueKey, "ABC-1")
        XCTAssertEqual(n.actorDisplayName, "Other Person")
        XCTAssertFalse(n.isRead)
    }

    func testStatusChangeDetected() throws {
        let raw = try issues(#"""
        [{
          "id": "10001", "key": "ABC-1",
          "fields": { "summary": "Fix the thing", "created": "2026-07-01T09:00:00.000+0000", "updated": "2026-07-16T10:00:00.000+0000" },
          "changelog": { "histories": [{
            "id": "8001", "author": { "accountId": "acc-other", "displayName": "Other Person" },
            "created": "2026-07-16T09:58:00.000+0000",
            "items": [{ "field": "status", "from": "1", "to": "3", "fromString": "To Do", "toString": "In Progress" }]
          }] }
        }]
        """#)

        let state = NotificationSyncState(cursor: date("2026-07-16T09:00:00.000+0000"), accountId: me)
        let (notifications, _) = NotificationDiffer.diff(issues: raw, state: state, myAccountId: me)

        XCTAssertEqual(notifications.count, 1)
        XCTAssertEqual(notifications.first?.kind, .statusChanged(from: "To Do", to: "In Progress"))
    }

    func testFieldUpdatedFoldsMultipleItemsIntoOneNotification() throws {
        let raw = try issues(#"""
        [{
          "id": "10001", "key": "ABC-1",
          "fields": { "summary": "Fix the thing", "created": "2026-07-01T09:00:00.000+0000", "updated": "2026-07-16T10:00:00.000+0000" },
          "changelog": { "histories": [{
            "id": "8001", "author": { "accountId": "acc-other", "displayName": "Other Person" },
            "created": "2026-07-16T09:58:00.000+0000",
            "items": [
              { "field": "Fix versions", "from": null, "to": null, "fromString": null, "toString": "v1.2" },
              { "field": "Sprint", "from": null, "to": null, "fromString": null, "toString": "Sprint 5" }
            ]
          }] }
        }]
        """#)

        let state = NotificationSyncState(cursor: date("2026-07-16T09:00:00.000+0000"), accountId: me)
        let (notifications, _) = NotificationDiffer.diff(issues: raw, state: state, myAccountId: me)

        // One notification per history entry, not per item.
        XCTAssertEqual(notifications.count, 1)
        XCTAssertEqual(notifications.first?.kind, .fieldUpdated(field: "Fix versions"))
    }

    // MARK: - Comments

    func testCommentByOtherUserIsCommented() throws {
        let raw = try issues(#"""
        [{
          "id": "10001", "key": "ABC-1",
          "fields": {
            "summary": "Fix the thing", "created": "2026-07-01T09:00:00.000+0000", "updated": "2026-07-16T10:00:00.000+0000",
            "comment": { "comments": [{
              "id": "9001", "author": { "accountId": "acc-other", "displayName": "Other Person" },
              "created": "2026-07-16T09:55:00.000+0000",
              "body": { "type": "doc", "version": 1, "content": [{ "type": "paragraph", "content": [{ "type": "text", "text": "Looks good" }] }] }
            }], "total": 1 }
          }
        }]
        """#)

        let state = NotificationSyncState(cursor: date("2026-07-16T09:00:00.000+0000"), accountId: me)
        let (notifications, _) = NotificationDiffer.diff(issues: raw, state: state, myAccountId: me)

        XCTAssertEqual(notifications.count, 1)
        let n = try XCTUnwrap(notifications.first)
        XCTAssertEqual(n.id, "10001.comment.9001")
        XCTAssertEqual(n.kind, .commented(excerpt: nil))
        XCTAssertEqual(n.actorDisplayName, "Other Person")
    }

    func testCommentMentioningMeIsMentioned() throws {
        let raw = try issues(#"""
        [{
          "id": "10001", "key": "ABC-1",
          "fields": {
            "summary": "Fix the thing", "created": "2026-07-01T09:00:00.000+0000", "updated": "2026-07-16T10:00:00.000+0000",
            "comment": { "comments": [{
              "id": "9001", "author": { "accountId": "acc-other", "displayName": "Other Person" },
              "created": "2026-07-16T09:55:00.000+0000",
              "body": {
                "type": "doc", "version": 1,
                "content": [{ "type": "paragraph", "content": [
                  { "type": "mention", "attrs": { "id": "acc-me", "text": "@Me" } }
                ] }]
              }
            }], "total": 1 }
          }
        }]
        """#)

        let state = NotificationSyncState(cursor: date("2026-07-16T09:00:00.000+0000"), accountId: me)
        let (notifications, _) = NotificationDiffer.diff(issues: raw, state: state, myAccountId: me)

        XCTAssertEqual(notifications.count, 1)
        XCTAssertEqual(notifications.first?.kind, .mentioned(excerpt: nil))
    }

    // MARK: - Suppression

    func testSelfAuthoredChangelogAndCommentAreSuppressed() throws {
        let raw = try issues(#"""
        [{
          "id": "10001", "key": "ABC-1",
          "fields": {
            "summary": "Fix the thing", "created": "2026-07-01T09:00:00.000+0000", "updated": "2026-07-16T10:00:00.000+0000",
            "comment": { "comments": [{
              "id": "9001", "author": { "accountId": "acc-me", "displayName": "Me" },
              "created": "2026-07-16T09:55:00.000+0000",
              "body": null
            }], "total": 1 }
          },
          "changelog": { "histories": [{
            "id": "8001", "author": { "accountId": "acc-me", "displayName": "Me" },
            "created": "2026-07-16T09:58:00.000+0000",
            "items": [{ "field": "status", "from": "1", "to": "3", "fromString": "To Do", "toString": "In Progress" }]
          }] }
        }]
        """#)

        let state = NotificationSyncState(cursor: date("2026-07-16T09:00:00.000+0000"), accountId: me)
        let (notifications, _) = NotificationDiffer.diff(issues: raw, state: state, myAccountId: me)

        XCTAssertTrue(notifications.isEmpty, "own changelog + own comment must not surface as notifications")
    }

    func testAlreadySeenIdsAreSuppressed() throws {
        let raw = try issues(#"""
        [{
          "id": "10001", "key": "ABC-1",
          "fields": { "summary": "Fix the thing", "created": "2026-07-01T09:00:00.000+0000", "updated": "2026-07-16T10:00:00.000+0000" },
          "changelog": { "histories": [{
            "id": "8001", "author": { "accountId": "acc-other", "displayName": "Other Person" },
            "created": "2026-07-16T09:58:00.000+0000",
            "items": [{ "field": "status", "from": "1", "to": "3", "fromString": "To Do", "toString": "In Progress" }]
          }] }
        }]
        """#)

        let state = NotificationSyncState(
            cursor: date("2026-07-16T09:00:00.000+0000"),
            accountId: me,
            seenIds: ["10001.changelog.8001"]
        )
        let (notifications, newState) = NotificationDiffer.diff(issues: raw, state: state, myAccountId: me)

        XCTAssertTrue(notifications.isEmpty)
        XCTAssertEqual(newState.seenIds, ["10001.changelog.8001"], "no duplicate insertion")
    }

    // MARK: - Cursor movement

    func testCursorAdvancesToMaxUpdatedAcrossIssues() throws {
        let raw = try issues(#"""
        [
          {
            "id": "10001", "key": "ABC-1",
            "fields": { "summary": "First", "created": "2026-07-01T09:00:00.000+0000", "updated": "2026-07-16T09:30:00.000+0000" }
          },
          {
            "id": "10002", "key": "ABC-2",
            "fields": { "summary": "Second", "created": "2026-07-01T09:00:00.000+0000", "updated": "2026-07-16T11:00:00.000+0000" }
          }
        ]
        """#)

        let state = NotificationSyncState(cursor: date("2026-07-16T08:00:00.000+0000"), accountId: me)
        let (_, newState) = NotificationDiffer.diff(issues: raw, state: state, myAccountId: me)

        XCTAssertEqual(newState.cursor, date("2026-07-16T11:00:00.000+0000"))
    }

    func testCursorNeverRegresses() throws {
        let raw = try issues(#"""
        [{
          "id": "10001", "key": "ABC-1",
          "fields": { "summary": "First", "created": "2026-07-01T09:00:00.000+0000", "updated": "2026-07-16T09:30:00.000+0000" }
        }]
        """#)

        // Cursor already ahead of the only returned issue's `updated`.
        let laterCursor = date("2026-07-16T12:00:00.000+0000")
        let state = NotificationSyncState(cursor: laterCursor, accountId: me)
        let (_, newState) = NotificationDiffer.diff(issues: raw, state: state, myAccountId: me)

        XCTAssertEqual(newState.cursor, laterCursor)
    }

    func testCursorUnchangedWhenNoIssuesReturned() {
        let cursor = date("2026-07-16T08:00:00.000+0000")
        let state = NotificationSyncState(cursor: cursor, accountId: me)
        let (notifications, newState) = NotificationDiffer.diff(issues: [], state: state, myAccountId: me)

        XCTAssertTrue(notifications.isEmpty)
        XCTAssertEqual(newState.cursor, cursor)
    }

    /// When paging stops at the page cap, `issues` (ordered newest-`updated`-
    /// first) doesn't hold the full result set — advancing to its max
    /// `updated` would permanently skip the unfetched, older-but-still-newer-
    /// than-cursor pages. `pageBudgetExhausted` should instead advance only to
    /// the minimum `updated` across the fetched issues.
    func testPageBudgetExhaustedAdvancesCursorToMinimumUpdatedNotMaximum() throws {
        let raw = try issues(#"""
        [
          {
            "id": "10001", "key": "ABC-1",
            "fields": { "summary": "Newest", "created": "2026-07-01T09:00:00.000+0000", "updated": "2026-07-16T11:00:00.000+0000" }
          },
          {
            "id": "10002", "key": "ABC-2",
            "fields": { "summary": "Oldest fetched", "created": "2026-07-01T09:00:00.000+0000", "updated": "2026-07-16T09:30:00.000+0000" }
          }
        ]
        """#)

        let state = NotificationSyncState(cursor: date("2026-07-16T08:00:00.000+0000"), accountId: me)
        let (_, newState) = NotificationDiffer.diff(
            issues: raw, state: state, myAccountId: me, pageBudgetExhausted: true
        )

        // The oldest fetched issue's `updated`, not the newest — everything
        // between it and the previous cursor is re-covered by the next poll.
        XCTAssertEqual(newState.cursor, date("2026-07-16T09:30:00.000+0000"))
    }

    /// Even in the truncated case, the cursor must never move backwards —
    /// e.g. a previous poll already advanced past everything this page holds.
    func testPageBudgetExhaustedNeverRegressesCursor() throws {
        let raw = try issues(#"""
        [{
          "id": "10001", "key": "ABC-1",
          "fields": { "summary": "First", "created": "2026-07-01T09:00:00.000+0000", "updated": "2026-07-16T09:30:00.000+0000" }
        }]
        """#)

        let laterCursor = date("2026-07-16T12:00:00.000+0000")
        let state = NotificationSyncState(cursor: laterCursor, accountId: me)
        let (_, newState) = NotificationDiffer.diff(
            issues: raw, state: state, myAccountId: me, pageBudgetExhausted: true
        )

        XCTAssertEqual(newState.cursor, laterCursor)
    }

    // MARK: - seenIds cap

    func testSeenIdsCappedAt500() throws {
        let raw = try issues(#"""
        [{
          "id": "10001", "key": "ABC-1",
          "fields": { "summary": "First", "created": "2026-07-01T09:00:00.000+0000", "updated": "2026-07-16T10:00:00.000+0000" },
          "changelog": { "histories": [{
            "id": "8001", "author": { "accountId": "acc-other", "displayName": "Other Person" },
            "created": "2026-07-16T09:58:00.000+0000",
            "items": [{ "field": "status", "from": "1", "to": "3", "fromString": "To Do", "toString": "In Progress" }]
          }] }
        }]
        """#)

        let existing = (0..<500).map { "seed.\($0)" }
        let state = NotificationSyncState(cursor: date("2026-07-16T09:00:00.000+0000"), accountId: me, seenIds: existing)
        let (notifications, newState) = NotificationDiffer.diff(issues: raw, state: state, myAccountId: me)

        XCTAssertEqual(notifications.count, 1)
        XCTAssertEqual(newState.seenIds.count, 500)
        XCTAssertEqual(newState.seenIds.last, "10001.changelog.8001")
        XCTAssertEqual(newState.seenIds.first, "seed.1", "oldest entry dropped to make room")
    }

    // MARK: - Sorting

    func testResultsSortedNewestFirst() throws {
        let raw = try issues(#"""
        [{
          "id": "10001", "key": "ABC-1",
          "fields": {
            "summary": "Fix the thing", "created": "2026-07-01T09:00:00.000+0000", "updated": "2026-07-16T10:00:00.000+0000",
            "comment": { "comments": [{
              "id": "9001", "author": { "accountId": "acc-other", "displayName": "Other Person" },
              "created": "2026-07-16T09:50:00.000+0000",
              "body": null
            }], "total": 1 }
          },
          "changelog": { "histories": [{
            "id": "8001", "author": { "accountId": "acc-other", "displayName": "Other Person" },
            "created": "2026-07-16T09:58:00.000+0000",
            "items": [{ "field": "status", "from": "1", "to": "3", "fromString": "To Do", "toString": "In Progress" }]
          }] }
        }]
        """#)

        let state = NotificationSyncState(cursor: date("2026-07-16T09:00:00.000+0000"), accountId: me)
        let (notifications, _) = NotificationDiffer.diff(issues: raw, state: state, myAccountId: me)

        XCTAssertEqual(notifications.map(\.id), ["10001.changelog.8001", "10001.comment.9001"])
    }
}

/// Test-only date parsing matching the Jira wire format used throughout these fixtures.
private enum JiraDate {
    static func parse(_ iso: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        guard let date = formatter.date(from: iso) else {
            fatalError("Invalid test fixture date: \(iso)")
        }
        return date
    }
}
