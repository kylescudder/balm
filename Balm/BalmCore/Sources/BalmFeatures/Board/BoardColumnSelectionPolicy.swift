import Foundation
import BalmModels

enum BoardColumnSelectionPolicy {
    static func preferredColumnID(
        current: String?,
        selectedIssue: JiraIssue?,
        columns: [BoardColumn]
    ) -> String? {
        let columnIDs = Set(columns.map(\.id))
        if let current, columnIDs.contains(current) {
            return current
        }
        if let selectedIssue {
            let issueColumnID = StatusNormaliser.normalise(selectedIssue.status.name)
            if columnIDs.contains(issueColumnID) {
                return issueColumnID
            }
            if let containingColumn = columns.first(where: { column in
                column.issues.contains(where: { $0.key == selectedIssue.key })
            }) {
                return containingColumn.id
            }
        }
        return columns.first?.id
    }
}
