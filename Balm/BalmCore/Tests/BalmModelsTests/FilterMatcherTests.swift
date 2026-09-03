import XCTest
@testable import BalmModels

final class FilterMatcherTests: XCTestCase {
    private func issue(
        status: String = "In Progress",
        assignee: String? = "Kyle Scudder",
        labels: [String] = [],
        fixVersions: [String] = [],
        dueDate: String? = nil
    ) -> JiraIssue {
        JiraIssue(
            id: "1",
            key: "BALM-1",
            summary: "Test",
            status: JiraStatus(name: status, statusCategory: JiraStatusCategory(key: "indeterminate", colorName: "blue")),
            priority: JiraPriority(name: "Medium"),
            assignee: assignee.map { JiraUserSummary(displayName: $0) },
            issueType: JiraIssueType(name: "Task"),
            dueDate: dueDate,
            labels: labels,
            fixVersions: fixVersions.map { JiraVersion(id: $0, name: $0, released: false, archived: false) }
        )
    }

    private func cond(_ field: FilterField, _ op: FilterOperator, _ values: [String] = []) -> FilterCondition {
        FilterCondition(field: field, op: op, values: values)
    }

    private func and(_ conditions: FilterCondition...) -> FilterDefinition {
        .structured(FilterGroup(rows: conditions.map { FilterRow(connector: .and, node: .condition($0)) }))
    }

    func testAssigneeByDisplayNameAndUnassignedSentinel() {
        let me = cond(.assignee, .isAnyOf, ["Kyle Scudder"])
        XCTAssertTrue(FilterMatcher.matches(issue(), condition: me))
        XCTAssertFalse(FilterMatcher.matches(issue(assignee: "Amara Okafor"), condition: me))
        XCTAssertFalse(FilterMatcher.matches(issue(assignee: nil), condition: me))

        let unassigned = cond(.assignee, .isAnyOf, [FilterOptions.unassignedSentinel])
        XCTAssertTrue(FilterMatcher.matches(issue(assignee: nil), condition: unassigned))
        XCTAssertFalse(FilterMatcher.matches(issue(), condition: unassigned))
    }

    func testStatusMatchesRawOrNormalisedName() {
        let filter = cond(.status, .isAnyOf, ["In Progress"])
        XCTAssertTrue(FilterMatcher.matches(issue(status: "in progress"), condition: filter))
        XCTAssertTrue(FilterMatcher.matches(issue(status: "InProgress"), condition: filter))
        XCTAssertFalse(FilterMatcher.matches(issue(status: "Done"), condition: filter))
    }

    func testIsNoneOfAndEmptiness() {
        XCTAssertTrue(FilterMatcher.matches(issue(status: "Done"), condition: cond(.status, .isNoneOf, ["To Do", "Blocked"])))
        XCTAssertFalse(FilterMatcher.matches(issue(status: "Blocked"), condition: cond(.status, .isNoneOf, ["To Do", "Blocked"])))
        XCTAssertTrue(FilterMatcher.matches(issue(labels: []), condition: cond(.labels, .isEmpty)))
        XCTAssertTrue(FilterMatcher.matches(issue(labels: ["macos"]), condition: cond(.labels, .isNotEmpty)))
        XCTAssertTrue(FilterMatcher.matches(issue(fixVersions: []), condition: cond(.release, .isAnyOf, [JiraVersion.noReleaseSentinel])))
    }

    func testDueDateOperatorsAreInclusiveLikeTheJQLBuilder() {
        let due = issue(dueDate: "2026-09-12")
        XCTAssertTrue(FilterMatcher.matches(due, condition: cond(.dueDate, .before, ["2026-09-30"])))
        XCTAssertTrue(FilterMatcher.matches(due, condition: cond(.dueDate, .before, ["2026-09-12"])))
        XCTAssertFalse(FilterMatcher.matches(due, condition: cond(.dueDate, .before, ["2026-09-01"])))
        XCTAssertTrue(FilterMatcher.matches(due, condition: cond(.dueDate, .after, ["2026-09-01"])))
        XCTAssertTrue(FilterMatcher.matches(due, condition: cond(.dueDate, .after, ["2026-09-12"])))
        XCTAssertFalse(FilterMatcher.matches(due, condition: cond(.dueDate, .after, ["2026-09-13"])))
        XCTAssertTrue(FilterMatcher.matches(due, condition: cond(.dueDate, .on, ["2026-09-12"])))
        XCTAssertTrue(FilterMatcher.matches(issue(), condition: cond(.dueDate, .isEmpty)))
    }

    func testAndBindsTighterThanOr() {
        // status = Done AND assignee = Amara  OR  labels contains macos
        let group = FilterGroup(rows: [
            FilterRow(connector: .and, node: .condition(cond(.status, .isAnyOf, ["Done"]))),
            FilterRow(connector: .and, node: .condition(cond(.assignee, .isAnyOf, ["Amara Okafor"]))),
            FilterRow(connector: .or, node: .condition(cond(.labels, .isAnyOf, ["macos"])))
        ])
        XCTAssertTrue(FilterMatcher.matches(issue(status: "In Progress", labels: ["macos"]), group: group))
        XCTAssertTrue(FilterMatcher.matches(issue(status: "Done", assignee: "Amara Okafor"), group: group))
        XCTAssertFalse(FilterMatcher.matches(issue(status: "Done", assignee: "Kyle Scudder"), group: group))
    }

    func testDefinitionLevelResults() {
        XCTAssertEqual(FilterMatcher.matches(issue(), .empty), true)
        XCTAssertNil(FilterMatcher.matches(issue(), .jql("resolution = Unresolved")))
        XCTAssertEqual(FilterMatcher.matches(issue(), .jql("   ")), true)
        XCTAssertEqual(FilterMatcher.matches(issue(assignee: "Amara Okafor"), and(cond(.assignee, .isAnyOf, ["Kyle Scudder"]))), false)
    }

    func testFailingConditionsNamesTheCulprits() {
        let definition = and(cond(.assignee, .isAnyOf, ["Kyle Scudder"]), cond(.status, .isAnyOf, ["In Progress"]))
        let failing = FilterMatcher.failingConditions(issue(status: "Done", assignee: "Amara Okafor"), in: definition)
        XCTAssertEqual(failing.map(\.field), [.assignee, .status])
        XCTAssertEqual(FilterMatcher.failingConditions(issue(), in: definition), [])
        XCTAssertEqual(FilterMatcher.failingConditions(issue(), in: .jql("x = y")), [])
    }
}
