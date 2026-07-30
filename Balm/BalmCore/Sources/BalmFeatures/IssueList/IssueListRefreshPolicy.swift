import Foundation
import BalmModels

enum IssueListRefreshPolicy {
    static func replacementIssues(
        current: [JiraIssue],
        fresh: [JiraIssue],
        isUserVisibleRefresh: Bool
    ) -> [JiraIssue] {
        guard !isUserVisibleRefresh, !current.isEmpty else { return fresh }
        if fresh.isEmpty {
            return current
        }
        let currentKeys = Set(current.map(\.key))
        let freshKeys = Set(fresh.map(\.key))
        if fresh.count < current.count, freshKeys.isSubset(of: currentKeys) {
            return current
        }
        return fresh
    }
}
