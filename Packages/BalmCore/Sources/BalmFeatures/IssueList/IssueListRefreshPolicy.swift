import Foundation
import BalmModels

enum IssueListRefreshPolicy {
    static func replacementIssues(
        current: [JiraIssue],
        fresh: [JiraIssue],
        isUserVisibleRefresh: Bool
    ) -> [JiraIssue] {
        if !isUserVisibleRefresh, !current.isEmpty, fresh.isEmpty {
            return current
        }
        return fresh
    }
}
