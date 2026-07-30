import XCTest
@testable import BalmAPI

final class NotificationSyncWindowTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testNilCursorBackfillsOneDay() {
        XCTAssertEqual(NotificationSyncWindow.minutes(cursor: nil, now: now), 1440)
    }

    func testRecentCursorAddsOverlap() {
        // 5 minutes elapsed + 2 minute overlap = 7.
        let cursor = now.addingTimeInterval(-5 * 60)
        XCTAssertEqual(NotificationSyncWindow.minutes(cursor: cursor, now: now), 7)
    }

    func testClampsAtMinimum() {
        // 0 minutes elapsed + 2 minute overlap = 2, clamped up to the floor of 3.
        XCTAssertEqual(NotificationSyncWindow.minutes(cursor: now, now: now), 3)
    }

    func testClampsAtMaximum() {
        // 30 days elapsed would blow past the 14-day ceiling.
        let cursor = now.addingTimeInterval(-30 * 24 * 60 * 60)
        XCTAssertEqual(NotificationSyncWindow.minutes(cursor: cursor, now: now), 20160)
    }

    func testJQLStringForBackfill() {
        XCTAssertEqual(
            NotificationSyncWindow.jql(cursor: nil, now: now),
            "(assignee = currentUser() OR reporter = currentUser() OR watcher = currentUser())"
                + " AND updated >= -1440m ORDER BY updated DESC"
        )
    }

    func testJQLStringForRecentCursor() {
        let cursor = now.addingTimeInterval(-5 * 60)
        XCTAssertEqual(
            NotificationSyncWindow.jql(cursor: cursor, now: now),
            "(assignee = currentUser() OR reporter = currentUser() OR watcher = currentUser())"
                + " AND updated >= -7m ORDER BY updated DESC"
        )
    }
}
