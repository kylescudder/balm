import Foundation
import BalmModels

struct IssueListCacheKey: Hashable, Sendable {
    let projectID: String
    let sprintNames: [String]
    let definition: FilterDefinition

    init(projectID: String, sprintNames: [String], definition: FilterDefinition) {
        self.projectID = projectID
        self.sprintNames = sprintNames.sorted { $0.localizedCompare($1) == .orderedAscending }
        self.definition = definition
    }
}

struct IssueListCache: Sendable {
    private var entries: [IssueListCacheKey: [JiraIssue]] = [:]

    func issues(for key: IssueListCacheKey) -> [JiraIssue]? {
        entries[key]
    }

    mutating func store(_ issues: [JiraIssue], for key: IssueListCacheKey) {
        entries[key] = issues
    }

    mutating func update(_ issue: JiraIssue) {
        for key in entries.keys {
            guard let index = entries[key]?.firstIndex(where: { $0.key == issue.key }) else { continue }
            entries[key]?[index] = issue
        }
    }
}
