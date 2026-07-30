import XCTest
@testable import BalmFeatures
import BalmModels

final class IssueListRefreshPolicyTests: XCTestCase {
    func testPassiveBackgroundRefreshDoesNotReplaceVisibleIssuesWithEmptyResult() {
        let existing = [Self.issue(key: "MPRO5-1")]

        let result = IssueListRefreshPolicy.replacementIssues(
            current: existing,
            fresh: [],
            isUserVisibleRefresh: false
        )

        XCTAssertEqual(result, existing)
    }

    func testUserVisibleRefreshCanReplaceIssuesWithEmptyResult() {
        let existing = [Self.issue(key: "MPRO5-1")]

        let result = IssueListRefreshPolicy.replacementIssues(
            current: existing,
            fresh: [],
            isUserVisibleRefresh: true
        )

        XCTAssertEqual(result, [])
    }

    func testPassiveBackgroundRefreshDoesNotReplaceVisibleIssuesWithStrictSubset() {
        let existing = [
            Self.issue(key: "MPRO5-1"),
            Self.issue(key: "MPRO5-2"),
            Self.issue(key: "MPRO5-3")
        ]
        let partial = [Self.issue(key: "MPRO5-1")]

        let result = IssueListRefreshPolicy.replacementIssues(
            current: existing,
            fresh: partial,
            isUserVisibleRefresh: false
        )

        XCTAssertEqual(result, existing)
    }

    func testPassiveBackgroundRefreshAppliesChangedNonSubsetResult() {
        let existing = [Self.issue(key: "MPRO5-1")]
        let fresh = [Self.issue(key: "MPRO5-2")]

        let result = IssueListRefreshPolicy.replacementIssues(
            current: existing,
            fresh: fresh,
            isUserVisibleRefresh: false
        )

        XCTAssertEqual(result, fresh)
    }

    private static func issue(key: String) -> JiraIssue {
        JiraIssue(
            id: key,
            key: key,
            summary: "Summary",
            status: JiraStatus(name: "To Do", statusCategory: .init(key: "new", colorName: "blue-gray")),
            priority: JiraPriority(name: "Medium"),
            issueType: JiraIssueType(name: "Task")
        )
    }
}
