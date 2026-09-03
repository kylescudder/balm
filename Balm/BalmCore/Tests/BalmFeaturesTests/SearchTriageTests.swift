import XCTest
@testable import BalmFeatures
import BalmModels

final class SearchTriageTests: XCTestCase {
    private func issue(_ key: String, status: String = "In Progress", assignee: String? = "Kyle Scudder", sprint: String? = "Sprint 42") -> JiraIssue {
        JiraIssue(
            id: key,
            key: key,
            summary: key,
            status: JiraStatus(name: status, statusCategory: JiraStatusCategory(key: "indeterminate", colorName: "blue")),
            priority: JiraPriority(name: "Medium"),
            assignee: assignee.map { JiraUserSummary(displayName: $0) },
            issueType: JiraIssueType(name: "Task"),
            sprint: sprint.map { JiraSprint(id: $0, name: $0, state: "active") }
        )
    }

    private let myIssues = FilterDefinition.structured(FilterGroup(rows: [
        FilterRow(node: .condition(FilterCondition(field: .assignee, op: .isAnyOf, values: ["Kyle Scudder"])))
    ]))

    private func scope(loaded: [String] = [], definition: FilterDefinition? = nil, sprints: [String] = ["Sprint 42"]) -> SearchScope {
        SearchScope(activeProjectKey: "BALM", selectedSprintNames: sprints, loadedKeys: Set(loaded), definition: definition ?? myIssues)
    }

    func testProjectIsAttributedBeforeSprintOrFilter() {
        let reason = SearchTriage.reason(for: issue("SITE-1", assignee: "Amara Okafor", sprint: nil), scope: scope())
        XCTAssertEqual(reason, .otherProject(projectKey: "SITE"))
    }

    func testSprintIsAttributedBeforeFilter() {
        XCTAssertEqual(
            SearchTriage.reason(for: issue("BALM-1", assignee: "Amara Okafor", sprint: "Sprint 39"), scope: scope()),
            .outsideSprints(sprintName: "Sprint 39")
        )
        XCTAssertEqual(
            SearchTriage.reason(for: issue("BALM-2", sprint: nil), scope: scope()),
            .outsideSprints(sprintName: nil)
        )
        // Backlog counts as a sprint when it is selected.
        XCTAssertEqual(
            SearchTriage.reason(for: issue("BALM-2", sprint: nil), scope: scope(loaded: ["BALM-2"], sprints: ["Backlog"])),
            .matchedElsewhere(loaded: true)
        )
    }

    func testFilterNamesTheFailingCondition() {
        let reason = SearchTriage.reason(for: issue("BALM-3", assignee: "Amara Okafor"), scope: scope())
        guard case .filtered(.conditions(let failing)) = reason else { return XCTFail("expected a filtered reason, got \(reason)") }
        XCTAssertEqual(failing.map(\.field), [.assignee])
    }

    func testRawJQLIsBlamedOnlyWhenTheIssueIsNotLoaded() {
        let jql = FilterDefinition.jql("resolution = Unresolved")
        XCTAssertEqual(SearchTriage.reason(for: issue("BALM-4"), scope: scope(definition: jql)), .filtered(.jql))
        XCTAssertEqual(SearchTriage.reason(for: issue("BALM-4"), scope: scope(loaded: ["BALM-4"], definition: jql)), .matchedElsewhere(loaded: true))
    }

    func testInScopeHitsAreMatchedElsewhereOrNotLoaded() {
        XCTAssertEqual(SearchTriage.reason(for: issue("BALM-5"), scope: scope(loaded: ["BALM-5"])), .matchedElsewhere(loaded: true))
        XCTAssertEqual(SearchTriage.reason(for: issue("BALM-6"), scope: scope()), .matchedElsewhere(loaded: false))
    }

    func testGroupsFollowDisplayOrderAndSkipEmptyGroups() {
        let hits = [
            issue("BALM-7"),
            issue("SITE-2"),
            issue("BALM-8", assignee: "Amara Okafor"),
            issue("BALM-9", sprint: nil)
        ]
        let groups = SearchTriage.groups(for: hits, scope: scope())
        XCTAssertEqual(groups.map(\.kind), [.filtered, .outsideSprints, .otherProject, .matchedElsewhere])
        XCTAssertEqual(groups.first { $0.kind == .filtered }?.results.map(\.id), ["BALM-8"])
    }
}
