import XCTest
@testable import BalmModels

final class FilterDefinitionTests: XCTestCase {
    private func cond(_ field: FilterField, _ op: FilterOperator, _ values: [String] = []) -> FilterCondition {
        FilterCondition(field: field, op: op, values: values)
    }

    func testEmptyIsEmpty() {
        XCTAssertTrue(FilterDefinition.empty.isEmpty)
        XCTAssertEqual(FilterDefinition.empty.activeCount, 0)
    }

    func testStructuredActiveCountIsTopLevelChildren() {
        let inner = FilterGroup(combinator: .any, children: [
            .condition(cond(.labels, .isAnyOf, ["a"])),
            .condition(cond(.labels, .isAnyOf, ["b"]))
        ])
        let root = FilterGroup(combinator: .all, children: [
            .condition(cond(.status, .isAnyOf, ["To Do"])),
            .group(inner)
        ])
        let def = FilterDefinition.structured(root)
        XCTAssertFalse(def.isEmpty)
        XCTAssertEqual(def.activeCount, 2) // one condition + one group at top level
    }

    func testJQLEmptinessAndCount() {
        XCTAssertTrue(FilterDefinition.jql("   \n").isEmpty)
        XCTAssertEqual(FilterDefinition.jql("   ").activeCount, 0)
        XCTAssertFalse(FilterDefinition.jql("labels = x").isEmpty)
        XCTAssertEqual(FilterDefinition.jql("labels = x").activeCount, 1)
    }

    func testNestedCodableRoundTrip() throws {
        let inner = FilterGroup(combinator: .any, children: [
            .condition(cond(.dueDate, .isNotEmpty)),
            .condition(cond(.labels, .isAnyOf, ["jira_escalated"]))
        ])
        let root = FilterGroup(combinator: .all, children: [
            .condition(cond(.status, .isAnyOf, ["In Progress"])),
            .group(inner)
        ])
        let def = FilterDefinition.structured(root)

        let data = try JSONEncoder().encode(def)
        let decoded = try JSONDecoder().decode(FilterDefinition.self, from: data)
        XCTAssertEqual(def, decoded)
    }

    func testJQLCodableRoundTrip() throws {
        let def = FilterDefinition.jql("resolution = Unresolved")
        let data = try JSONEncoder().encode(def)
        XCTAssertEqual(try JSONDecoder().decode(FilterDefinition.self, from: data), def)
    }

    func testSavedFilterCodableRoundTrip() throws {
        let saved = SavedFilter(name: "Escalated", definition: .jql("labels = jira_escalated"))
        let data = try JSONEncoder().encode(saved)
        XCTAssertEqual(try JSONDecoder().decode(SavedFilter.self, from: data), saved)
    }

    func testMigrationMapsSectionsToConditions() {
        let legacy = FilterOptions(
            status: ["To Do"],
            assignee: ["UNASSIGNED"],
            reporter: ["someone"],
            dueDateFrom: "2026-01-01"
        )
        let group = legacy.asFilterGroup
        XCTAssertEqual(group.combinator, .all)
        // status, assignee, dueDate(after), reporter — in legacy order
        XCTAssertEqual(group.children.count, 4)
        guard case .condition(let first) = group.children[0] else { return XCTFail("expected condition") }
        XCTAssertEqual(first.field, .status)
        XCTAssertEqual(first.op, .isAnyOf)
    }

    func testMigrationEmptyIsEmptyGroup() {
        XCTAssertTrue(FilterOptions.empty.asFilterGroup.isEmpty)
        XCTAssertTrue(FilterOptions.empty.asFilterDefinition.isEmpty)
    }
}
