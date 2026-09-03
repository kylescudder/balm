import XCTest
@testable import BalmFeatures
import BalmModels

final class IssueHealthSectionsTests: XCTestCase {
    private func issue(_ key: String, status: String) -> JiraIssue {
        JiraIssue(
            id: key,
            key: key,
            summary: key,
            status: JiraStatus(name: status, statusCategory: JiraStatusCategory(key: "new", colorName: "blue")),
            priority: JiraPriority(name: "Medium"),
            issueType: JiraIssueType(name: "Task")
        )
    }

    func testGroupsByHealthInDisplayOrder() {
        let issues = [
            issue("A-1", status: "Done"),
            issue("A-2", status: "To Do"),
            issue("A-3", status: "In Progress"),
            issue("A-4", status: "Blocked"),
            issue("A-5", status: "Awaiting Testing"),
            issue("A-6", status: "In PR")
        ]
        let sections = IssueListViewModel.healthSections(from: issues)
        XCTAssertEqual(sections.map(\.health), [.notStarted, .blocked, .active, .waiting, .done])
        XCTAssertEqual(sections.first { $0.health == .active }?.issues.map(\.key), ["A-3", "A-6"])
    }

    func testOmitsEmptyGroupsAndKeepsFetchOrderWithinAGroup() {
        let issues = [
            issue("B-9", status: "In Progress"),
            issue("B-2", status: "In Review"),
            issue("B-5", status: "Current Active Issue")
        ]
        let sections = IssueListViewModel.healthSections(from: issues)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].issues.map(\.key), ["B-9", "B-2", "B-5"])
    }

    func testUnknownStatusesLandInToDo() {
        let sections = IssueListViewModel.healthSections(from: [issue("C-1", status: "Quantum Limbo")])
        XCTAssertEqual(sections.map(\.health), [.notStarted])
    }

    func testBoardColumnsPinTheWorkflowThenFollowHealthOrder() {
        let issues = [
            issue("D-1", status: "Done"),
            issue("D-2", status: "To Do"),
            issue("D-3", status: "In Review"),
            issue("D-4", status: "In Progress"),
            issue("D-5", status: "Blocked"),
            issue("D-6", status: "Awaiting Testing"),
            issue("D-7", status: "Declined"),
            issue("D-8", status: "Current Active Issue"),
            issue("D-9", status: "Iteration Required"),
            issue("D-10", status: "In PR")
        ]
        let columns = IssueListViewModel.columns(from: issues)
        XCTAssertEqual(
            columns.map(\.title),
            [
                "To Do", "Blocked", "Iteration Required", "In Progress", "Current Active Issue",
                "In PR", "In Review", "Awaiting Testing", "Done", "Declined"
            ]
        )
    }

    func testFinishedSprintsAreDroppedAndBacklogTakesOver() {
        let available = [JiraSprint.backlog, JiraSprint(id: "42", name: "Sprint 42", state: "active")]
        let result = IssueListViewModel.reconciledSprintSelection(["Sprint 41"], available: available)
        XCTAssertEqual(result.kept, ["Backlog"])
        XCTAssertEqual(result.removed, ["Sprint 41"])
    }

    func testSurvivingSprintsStaySelectedWhenOneFinishes() {
        let available = [JiraSprint.backlog, JiraSprint(id: "42", name: "Sprint 42", state: "active")]
        let result = IssueListViewModel.reconciledSprintSelection(["Sprint 41", "Sprint 42"], available: available)
        XCTAssertEqual(result.kept, ["Sprint 42"])
        XCTAssertEqual(result.removed, ["Sprint 41"])
    }

    func testValidSelectionIsUntouched() {
        let available = [JiraSprint.backlog, JiraSprint(id: "42", name: "Sprint 42", state: "active")]
        let result = IssueListViewModel.reconciledSprintSelection(["Sprint 42"], available: available)
        XCTAssertEqual(result.kept, ["Sprint 42"])
        XCTAssertTrue(result.removed.isEmpty)
        XCTAssertTrue(IssueListViewModel.reconciledSprintSelection([], available: available).removed.isEmpty)
    }
}
