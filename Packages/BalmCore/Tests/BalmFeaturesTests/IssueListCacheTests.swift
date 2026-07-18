import XCTest
@testable import BalmFeatures
import BalmModels

final class IssueListCacheTests: XCTestCase {
    func testCacheReturnsIssuesForSameProjectSprintAndFilterContext() {
        var cache = IssueListCache()
        let issue = Self.issue(key: "BALM-1")
        let key = IssueListCacheKey(projectID: "100", sprintNames: ["Sprint 2", "Sprint 1"], definition: .empty)

        cache.store([issue], for: key)

        XCTAssertEqual(cache.issues(for: key), [issue])
    }

    func testCacheNormalisesSprintOrder() {
        let lhs = IssueListCacheKey(projectID: "100", sprintNames: ["Sprint 2", "Sprint 1"], definition: .empty)
        let rhs = IssueListCacheKey(projectID: "100", sprintNames: ["Sprint 1", "Sprint 2"], definition: .empty)

        XCTAssertEqual(lhs, rhs)
    }

    func testCacheMissesDifferentFilterContexts() {
        var cache = IssueListCache()
        let issue = Self.issue(key: "BALM-1")
        let empty = IssueListCacheKey(projectID: "100", sprintNames: ["Sprint 1"], definition: .empty)
        let filtered = IssueListCacheKey(
            projectID: "100",
            sprintNames: ["Sprint 1"],
            definition: .jql("status = Done")
        )

        cache.store([issue], for: empty)

        XCTAssertNil(cache.issues(for: filtered))
    }

    @MainActor
    func testSharedCacheSurvivesIssueListViewModelRecreation() {
        SharedIssueListCache.reset()
        let issue = Self.issue(key: "BALM-1")
        let key = IssueListCacheKey(projectID: "100", sprintNames: ["Sprint 1"], definition: .empty)

        SharedIssueListCache.store([issue], for: key)

        XCTAssertEqual(SharedIssueListCache.issues(for: key), [issue])
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
