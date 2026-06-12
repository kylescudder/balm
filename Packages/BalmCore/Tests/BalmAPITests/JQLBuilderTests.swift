import XCTest
import BalmModels
@testable import BalmAPI

final class JQLBuilderTests: XCTestCase {
    private func make(_ filters: FilterOptions, project: String = "ABC") -> JQLBuilder {
        JQLBuilder(projectKey: project, filters: filters)
    }

    func testEmptySprintReturnsNil() {
        let b = make(FilterOptions(status: ["To Do"]))
        XCTAssertNil(b.build())
    }

    func testNamedSprintAppendsOrderBy() {
        let jql = make(FilterOptions(sprint: ["Sprint 1"])).build()
        XCTAssertEqual(jql, #"project = ABC AND sprint IN ("Sprint 1") order by created"#)
    }

    func testBacklogOnly() {
        let jql = make(FilterOptions(sprint: ["backlog"])).build()
        XCTAssertEqual(jql, "project = ABC AND sprint is EMPTY")
    }

    func testBacklogSentinelOnly() {
        let jql = make(FilterOptions(sprint: [JiraSprint.backlogSentinel])).build()
        XCTAssertEqual(jql, "project = ABC AND sprint is EMPTY")
    }

    func testBacklogPlusNamed() {
        let jql = make(FilterOptions(sprint: ["backlog", "Sprint 5"])).build()
        XCTAssertEqual(jql, #"project = ABC AND (sprint is EMPTY OR sprint IN ("Sprint 5"))"#)
    }

    func testAssigneeOrUnassigned() {
        let jql = make(FilterOptions(
            assignee: ["UNASSIGNED", "acc1"],
            sprint: ["Sprint 1"]
        )).build()
        XCTAssertEqual(
            jql,
            #"project = ABC AND sprint IN ("Sprint 1") AND (assignee is EMPTY OR assignee = "acc1") order by created"#
        )
    }

    func testReleaseOrNoRelease() {
        let jql = make(FilterOptions(
            release: ["NO_RELEASE", "v1.2"],
            sprint: ["Sprint 1"]
        )).build()
        XCTAssertEqual(
            jql,
            #"project = ABC AND sprint IN ("Sprint 1") AND (fixVersion is EMPTY OR fixVersion = "v1.2") order by created"#
        )
    }

    func testDueDateRange() {
        let jql = make(FilterOptions(
            sprint: ["Sprint 1"],
            dueDateFrom: "2026-01-01",
            dueDateTo: "2026-02-01"
        )).build()
        XCTAssertEqual(
            jql,
            #"project = ABC AND sprint IN ("Sprint 1") AND duedate >= "2026-01-01" AND duedate <= "2026-02-01" order by created"#
        )
    }

    func testEscapesQuotes() {
        let jql = make(FilterOptions(
            status: [#"P0 "high""#],
            sprint: ["Sprint 1"]
        )).build()
        XCTAssertEqual(
            jql,
            #"project = ABC AND sprint IN ("Sprint 1") AND status IN ("P0 \"high\"") order by created"#
        )
    }

    func testFullCombination() {
        let jql = make(FilterOptions(
            status: ["To Do"],
            priority: ["High"],
            assignee: ["acc1"],
            issueType: ["Bug"],
            labels: ["urgent"],
            components: ["api"],
            sprint: ["Sprint 1"],
            release: ["v1.0"]
        )).build()
        XCTAssertEqual(
            jql,
            #"project = ABC AND sprint IN ("Sprint 1") AND status IN ("To Do") AND priority IN ("High") AND (assignee = "acc1") AND issuetype IN ("Bug") AND labels IN ("urgent") AND component IN ("api") AND (fixVersion = "v1.0") order by created"#
        )
    }
}
