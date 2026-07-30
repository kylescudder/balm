import XCTest
import BalmModels
@testable import BalmAPI

final class JQLBuilderTests: XCTestCase {
    private func build(
        sprints: [String],
        _ definition: FilterDefinition = .empty,
        project: String = "ABC"
    ) -> String? {
        JQLBuilder(projectKey: project, sprints: sprints, definition: definition).build()
    }

    private func cond(_ field: FilterField, _ op: FilterOperator, _ values: [String] = []) -> FilterCondition {
        FilterCondition(field: field, op: op, values: values)
    }

    /// Flat group of leaf conditions joined by `connector` (the first row's
    /// connector is ignored).
    private func flat(_ conditions: [FilterCondition], _ connector: FilterConnector = .and) -> FilterDefinition {
        let rows = conditions.enumerated().map { index, condition in
            FilterRow(connector: index == 0 ? .and : connector, node: .condition(condition))
        }
        return .structured(FilterGroup(rows: rows))
    }

    // MARK: - Sprint scoping (unchanged contract)

    func testEmptySprintReturnsNil() {
        XCTAssertNil(build(sprints: [], flat([cond(.status, .isAnyOf, ["To Do"])])))
    }

    func testNamedSprintAppendsOrderBy() {
        XCTAssertEqual(build(sprints: ["Sprint 1"]), #"project = ABC AND sprint IN ("Sprint 1") order by created"#)
    }

    func testBacklogOnly() {
        XCTAssertEqual(build(sprints: ["backlog"]), "project = ABC AND sprint is EMPTY")
    }

    func testBacklogSentinelOnly() {
        XCTAssertEqual(build(sprints: [JiraSprint.backlogSentinel]), "project = ABC AND sprint is EMPTY")
    }

    func testBacklogPlusNamed() {
        XCTAssertEqual(
            build(sprints: ["backlog", "Sprint 5"]),
            #"project = ABC AND (sprint is EMPTY OR sprint IN ("Sprint 5"))"#
        )
    }

    func testEmptyDefinitionEqualsSprintOnly() {
        XCTAssertEqual(build(sprints: ["Sprint 1"], .empty), build(sprints: ["Sprint 1"]))
    }

    // MARK: - Structured conditions

    func testIsAnyOfSingle() {
        XCTAssertEqual(
            build(sprints: ["Sprint 1"], flat([cond(.status, .isAnyOf, ["To Do"])])),
            #"project = ABC AND sprint IN ("Sprint 1") AND status IN ("To Do") order by created"#
        )
    }

    func testIsNoneOf() {
        XCTAssertEqual(
            build(sprints: ["Sprint 1"], flat([cond(.status, .isNoneOf, ["Done"])])),
            #"project = ABC AND sprint IN ("Sprint 1") AND status NOT IN ("Done") order by created"#
        )
    }

    func testIsEmpty() {
        XCTAssertEqual(
            build(sprints: ["Sprint 1"], flat([cond(.assignee, .isEmpty)])),
            #"project = ABC AND sprint IN ("Sprint 1") AND assignee is EMPTY order by created"#
        )
    }

    func testAssigneeOrUnassigned() {
        XCTAssertEqual(
            build(sprints: ["Sprint 1"], flat([cond(.assignee, .isAnyOf, ["UNASSIGNED", "acc1"])])),
            #"project = ABC AND sprint IN ("Sprint 1") AND (assignee is EMPTY OR assignee = "acc1") order by created"#
        )
    }

    func testAssigneeNoneOfSentinel() {
        XCTAssertEqual(
            build(sprints: ["Sprint 1"], flat([cond(.assignee, .isNoneOf, ["UNASSIGNED", "acc1"])])),
            #"project = ABC AND sprint IN ("Sprint 1") AND (assignee is not EMPTY AND assignee != "acc1") order by created"#
        )
    }

    func testReleaseOrNoRelease() {
        XCTAssertEqual(
            build(sprints: ["Sprint 1"], flat([cond(.release, .isAnyOf, ["NO_RELEASE", "v1.2"])])),
            #"project = ABC AND sprint IN ("Sprint 1") AND (fixVersion is EMPTY OR fixVersion = "v1.2") order by created"#
        )
    }

    func testDueDateRange() {
        XCTAssertEqual(
            build(sprints: ["Sprint 1"], flat([
                cond(.dueDate, .after, ["2026-01-01"]),
                cond(.dueDate, .before, ["2026-02-01"])
            ])),
            #"project = ABC AND sprint IN ("Sprint 1") AND duedate >= "2026-01-01" AND duedate <= "2026-02-01" order by created"#
        )
    }

    func testEscapesQuotes() {
        XCTAssertEqual(
            build(sprints: ["Sprint 1"], flat([cond(.status, .isAnyOf, [#"P0 "high""#])])),
            #"project = ABC AND sprint IN ("Sprint 1") AND status IN ("P0 \"high\"") order by created"#
        )
    }

    // MARK: - OR across fields (the headline feature)

    func testNestedOrGroup() {
        // status AND (duedate is not empty OR labels = jira_escalated)
        let inner = FilterGroup(rows: [
            FilterRow(node: .condition(cond(.dueDate, .isNotEmpty))),
            FilterRow(connector: .or, node: .condition(cond(.labels, .isAnyOf, ["jira_escalated"])))
        ])
        let root = FilterGroup(rows: [
            FilterRow(node: .condition(cond(.status, .isAnyOf, ["In Progress"]))),
            FilterRow(connector: .and, node: .group(inner))
        ])
        XCTAssertEqual(
            build(sprints: ["Sprint 1"], .structured(root)),
            #"project = ABC AND sprint IN ("Sprint 1") AND status IN ("In Progress") AND (duedate is not EMPTY OR labels IN ("jira_escalated")) order by created"#
        )
    }

    func testTopLevelOrWraps() {
        XCTAssertEqual(
            build(sprints: ["Sprint 1"], flat([
                cond(.status, .isAnyOf, ["A"]),
                cond(.priority, .isAnyOf, ["High"])
            ], .or)),
            #"project = ABC AND sprint IN ("Sprint 1") AND (status IN ("A") OR priority IN ("High")) order by created"#
        )
    }

    func testMixedConnectorsRespectPrecedence() {
        // A AND B OR C  ==  (A AND B) OR C
        let rows = [
            FilterRow(node: .condition(cond(.status, .isAnyOf, ["A"]))),
            FilterRow(connector: .and, node: .condition(cond(.priority, .isAnyOf, ["High"]))),
            FilterRow(connector: .or, node: .condition(cond(.labels, .isAnyOf, ["urgent"])))
        ]
        XCTAssertEqual(
            build(sprints: ["Sprint 1"], .structured(FilterGroup(rows: rows))),
            #"project = ABC AND sprint IN ("Sprint 1") AND (status IN ("A") AND priority IN ("High") OR labels IN ("urgent")) order by created"#
        )
    }

    func testComponentFieldOverride() {
        let jql = JQLBuilder(
            projectKey: "ABC",
            sprints: ["Sprint 1"],
            definition: flat([cond(.components, .isAnyOf, ["Odyssey Web Client"])]),
            componentField: "cf[10312]"
        ).build()
        XCTAssertEqual(
            jql,
            #"project = ABC AND sprint IN ("Sprint 1") AND cf[10312] IN ("Odyssey Web Client") order by created"#
        )
    }

    func testComponentFieldDefaultsToStandard() {
        XCTAssertEqual(
            build(sprints: ["Sprint 1"], flat([cond(.components, .isAnyOf, ["api"])])),
            #"project = ABC AND sprint IN ("Sprint 1") AND component IN ("api") order by created"#
        )
    }

    // MARK: - Raw JQL fallback

    func testRawJQLScopedWithUserOrderBy() {
        let raw = #"resolution = Unresolved AND (duedate != EMPTY OR labels IN (jira_escalated)) ORDER BY duedate ASC, priority DESC"#
        XCTAssertEqual(
            build(sprints: ["Sprint 1"], .jql(raw)),
            #"project = ABC AND sprint IN ("Sprint 1") AND (resolution = Unresolved AND (duedate != EMPTY OR labels IN (jira_escalated))) order by duedate ASC, priority DESC"#
        )
    }

    func testRawJQLAppendsDefaultOrderBy() {
        XCTAssertEqual(
            build(sprints: ["Sprint 1"], .jql("labels = foo")),
            #"project = ABC AND sprint IN ("Sprint 1") AND (labels = foo) order by created"#
        )
    }

    func testRawJQLBlankEqualsSprintOnly() {
        XCTAssertEqual(
            build(sprints: ["Sprint 1"], .jql("   ")),
            #"project = ABC AND sprint IN ("Sprint 1") order by created"#
        )
    }

    // MARK: - Legacy migration parity (output must be byte-identical)

    func testMigratedFullCombination() {
        let legacy = FilterOptions(
            status: ["To Do"],
            priority: ["High"],
            assignee: ["acc1"],
            issueType: ["Bug"],
            labels: ["urgent"],
            components: ["api"],
            release: ["v1.0"]
        )
        XCTAssertEqual(
            build(sprints: ["Sprint 1"], legacy.asFilterDefinition),
            #"project = ABC AND sprint IN ("Sprint 1") AND status IN ("To Do") AND priority IN ("High") AND (assignee = "acc1") AND issuetype IN ("Bug") AND labels IN ("urgent") AND component IN ("api") AND (fixVersion = "v1.0") order by created"#
        )
    }

    func testMigratedDueDateRange() {
        let legacy = FilterOptions(dueDateFrom: "2026-01-01", dueDateTo: "2026-02-01")
        XCTAssertEqual(
            build(sprints: ["Sprint 1"], legacy.asFilterDefinition),
            #"project = ABC AND sprint IN ("Sprint 1") AND duedate >= "2026-01-01" AND duedate <= "2026-02-01" order by created"#
        )
    }

    func testMigratedAssigneeOrUnassigned() {
        let legacy = FilterOptions(assignee: ["UNASSIGNED", "acc1"])
        XCTAssertEqual(
            build(sprints: ["Sprint 1"], legacy.asFilterDefinition),
            #"project = ABC AND sprint IN ("Sprint 1") AND (assignee is EMPTY OR assignee = "acc1") order by created"#
        )
    }
}
