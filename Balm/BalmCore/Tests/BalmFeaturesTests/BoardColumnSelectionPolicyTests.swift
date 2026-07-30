import XCTest
@testable import BalmFeatures
import BalmModels

final class BoardColumnSelectionPolicyTests: XCTestCase {
    func testKeepsCurrentColumnWhenItStillExists() {
        let columns = [
            Self.column(id: "To Do"),
            Self.column(id: "Awaiting Information")
        ]

        let result = BoardColumnSelectionPolicy.preferredColumnID(
            current: "Awaiting Information",
            selectedIssue: nil,
            columns: columns
        )

        XCTAssertEqual(result, "Awaiting Information")
    }

    func testFallsBackToSelectedIssueStatusColumnWhenCurrentColumnNoLongerExists() {
        let issue = Self.issue(key: "MPRO5-1", status: "Blocked")
        let columns = [
            Self.column(id: "To Do"),
            Self.column(id: "Blocked", issues: [issue])
        ]

        let result = BoardColumnSelectionPolicy.preferredColumnID(
            current: "Awaiting Information",
            selectedIssue: issue,
            columns: columns
        )

        XCTAssertEqual(result, "Blocked")
    }

    func testFallsBackToFirstColumnWhenNeitherCurrentNorSelectedIssueColumnExist() {
        let columns = [Self.column(id: "To Do"), Self.column(id: "Blocked")]

        let result = BoardColumnSelectionPolicy.preferredColumnID(
            current: nil,
            selectedIssue: nil,
            columns: columns
        )

        XCTAssertEqual(result, "To Do")
    }

    private static func column(id: String, issues: [JiraIssue] = []) -> BoardColumn {
        BoardColumn(id: id, title: id, statusKeys: [id], issues: issues)
    }

    private static func issue(key: String, status: String) -> JiraIssue {
        JiraIssue(
            id: key,
            key: key,
            summary: "Summary",
            status: JiraStatus(name: status, statusCategory: .init(key: "new", colorName: "blue-gray")),
            priority: JiraPriority(name: "Medium"),
            issueType: JiraIssueType(name: "Task")
        )
    }
}
