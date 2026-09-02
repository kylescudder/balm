import XCTest
@testable import BalmFeatures
import BalmModels

final class AvailableFilterOptionsTests: XCTestCase {

    // MARK: - Derivation

    func testStatusPoolCarriesEveryRawStatusOnTheIssues() {
        let options = AvailableFilterOptions.from([
            Self.issue(key: "MP5-1", status: "In Progress"),
            Self.issue(key: "MP5-2", status: "Done"),
            Self.issue(key: "MP5-3", status: "ITERATION REQUIRED")
        ])

        XCTAssertEqual(options.statuses, ["Done", "In Progress", "ITERATION REQUIRED"])
    }

    func testStatusPoolIsDedupedAndDropsEmptyNames() {
        let options = AvailableFilterOptions.from([
            Self.issue(key: "MP5-1", status: "Done"),
            Self.issue(key: "MP5-2", status: "Done"),
            Self.issue(key: "MP5-3", status: "")
        ])

        XCTAssertEqual(options.statuses, ["Done"])
    }

    // MARK: - Merging

    /// The regression this fix exists for: the unfiltered snapshot is throttled
    /// by sprint set, so a status first reached mid-sprint is absent from it
    /// while its column is on the board. The union must still offer it.
    func testMergingSurfacesAStatusPresentOnlyInTheLoadedIssues() {
        let snapshot = AvailableFilterOptions.from([
            Self.issue(key: "MP5-1", status: "In Progress"),
            Self.issue(key: "MP5-2", status: "To Do")
        ])
        let loaded = AvailableFilterOptions.from([
            Self.issue(key: "MP5-3", status: "Done")
        ])

        let merged = snapshot.merging(loaded)

        XCTAssertEqual(merged.statuses, ["Done", "In Progress", "To Do"])
    }

    func testMergingKeepsSnapshotValuesMissingFromTheLoadedIssues() {
        let snapshot = AvailableFilterOptions.from([
            Self.issue(key: "MP5-1", status: "Blocked"),
            Self.issue(key: "MP5-2", status: "Under Monitoring")
        ])
        let loaded = AvailableFilterOptions.from([
            Self.issue(key: "MP5-2", status: "Under Monitoring")
        ])

        let merged = snapshot.merging(loaded)

        XCTAssertEqual(merged.statuses, ["Blocked", "Under Monitoring"])
    }

    func testMergingIsIdempotentWhenBothSidesMatch() {
        let issues = [
            Self.issue(key: "MP5-1", status: "Done", priority: "High", labels: ["infra"]),
            Self.issue(key: "MP5-2", status: "To Do", priority: "Low", labels: ["ui"])
        ]
        let options = AvailableFilterOptions.from(issues)

        XCTAssertEqual(options.merging(options), options)
    }

    func testMergingUnionsEveryStringPool() {
        let snapshot = AvailableFilterOptions.from([
            Self.issue(
                key: "MP5-1",
                status: "To Do",
                priority: "Low",
                issueType: "Task",
                labels: ["infra"],
                components: ["API"],
                instanceName: "eu-1"
            )
        ])
        let loaded = AvailableFilterOptions.from([
            Self.issue(
                key: "MP5-2",
                status: "Done",
                priority: "High",
                issueType: "Bug",
                labels: ["ui"],
                components: ["Web"],
                instanceName: "us-1"
            )
        ])

        let merged = snapshot.merging(loaded)

        XCTAssertEqual(merged.statuses, ["Done", "To Do"])
        XCTAssertEqual(merged.priorities, ["High", "Low"])
        XCTAssertEqual(merged.issueTypes, ["Bug", "Task"])
        XCTAssertEqual(merged.labels, ["infra", "ui"])
        XCTAssertEqual(merged.components, ["API", "Web"])
        XCTAssertEqual(merged.instanceNames, ["eu-1", "us-1"])
    }

    func testMergingKeepsTheUnassignedSentinelFirstAndDedupesPeople() {
        let snapshot = AvailableFilterOptions.from([
            Self.issue(key: "MP5-1", status: "To Do", assignee: "Kyle Scudder")
        ])
        let loaded = AvailableFilterOptions.from([
            Self.issue(key: "MP5-2", status: "Done", assignee: "Kyle Scudder"),
            Self.issue(key: "MP5-3", status: "Done", assignee: "Ada Lovelace")
        ])

        let merged = snapshot.merging(loaded)

        XCTAssertEqual(
            merged.assignees.map(\.id),
            [FilterOptions.unassignedSentinel, "Kyle Scudder", "Ada Lovelace"]
        )
    }

    func testMergingKeepsTheNoReleaseSentinelFirstAndDedupesReleases() {
        let snapshot = AvailableFilterOptions.from(
            [Self.issue(key: "MP5-1", status: "To Do")],
            extraReleases: [JiraVersion(id: "1", name: "2026.1", released: false)]
        )
        let loaded = AvailableFilterOptions.from(
            [Self.issue(key: "MP5-2", status: "Done")],
            extraReleases: [
                JiraVersion(id: "1", name: "2026.1", released: false),
                JiraVersion(id: "2", name: "2026.2", released: false)
            ]
        )

        let merged = snapshot.merging(loaded)

        XCTAssertEqual(
            merged.releases.map(\.id),
            [JiraVersion.noReleaseSentinel, "2026.1", "2026.2"]
        )
    }

    func testMergingOntoAnEmptySnapshotYieldsTheLoadedPool() {
        let loaded = AvailableFilterOptions.from([
            Self.issue(key: "MP5-1", status: "Done")
        ])

        XCTAssertEqual(AvailableFilterOptions.empty.merging(loaded), loaded)
    }

    // MARK: - Menu labels

    /// `merging` works on raw Jira names; the menu normalises for display. A
    /// mid-sprint "Done" must therefore reach the Status menu as "Done".
    func testStatusMenuLabelsNormaliseTheMergedRawNames() {
        let snapshot = AvailableFilterOptions.from([
            Self.issue(key: "MP5-1", status: "In Progress")
        ])
        let loaded = AvailableFilterOptions.from([
            Self.issue(key: "MP5-2", status: "Done"),
            Self.issue(key: "MP5-3", status: "ITERATION REQUIRED")
        ])

        let labels = FilterBuilderMultiSelectOptions
            .multiSelectOptions(for: .status, from: snapshot.merging(loaded))
            .map(\.label)

        XCTAssertEqual(labels, ["Done", "In Progress", "Iteration Required"])
    }

    // MARK: - Fixtures

    private static func issue(
        key: String,
        status: String,
        priority: String = "Medium",
        issueType: String = "Task",
        assignee: String? = nil,
        labels: [String] = [],
        components: [String] = [],
        instanceName: String? = nil
    ) -> JiraIssue {
        JiraIssue(
            id: key,
            key: key,
            summary: "Summary",
            status: JiraStatus(name: status, statusCategory: .init(key: "new", colorName: "blue-gray")),
            priority: JiraPriority(name: priority),
            assignee: assignee.map { JiraUserSummary(displayName: $0) },
            issueType: JiraIssueType(name: issueType),
            labels: labels,
            components: components.map { JiraComponent(id: $0, name: $0) },
            instanceName: instanceName
        )
    }
}
