import Foundation
import BalmModels

public enum JiraIssueMapper {
    public static func issue(from raw: RawJiraIssue, instanceFieldID: String? = nil) -> JiraIssue {
        let f = raw.fields
        let components = dedupedComponents(
            standard: f.components ?? [],
            custom: f.customfield_10312?.components ?? []
        )
        // Prefer field names baked into the response (expand=names); fall back to
        // the externally resolved field id from JiraClient.resolveInstanceFieldID().
        let resolvedInstanceFieldID = raw.fieldNames.flatMap { names in
            names.first { $0.value.localizedCaseInsensitiveContains("Instance") }?.key
        } ?? instanceFieldID
        let instanceName = resolvedInstanceFieldID.flatMap { raw.customFieldStrings[$0] }
        return JiraIssue(
            id: raw.id,
            key: raw.key,
            summary: f.summary,
            descriptionText: nil,
            descriptionADF: nonEmpty(f.description?.rawJSON),
            status: f.status,
            priority: f.priority ?? JiraPriority(name: "Unprioritised"),
            assignee: f.assignee,
            reporter: f.reporter,
            issueType: f.issuetype,
            created: f.created,
            updated: f.updated,
            dueDate: f.duedate,
            labels: f.labels ?? [],
            components: components,
            sprint: extractSprint(from: raw),
            fixVersions: f.fixVersions ?? [],
            instanceName: instanceName
        )
    }

    /// Mirrors `extractComponentsFromFields` at `lib/jira-api.ts:399-419`.
    /// Merges `components` and custom field `10312`, deduping by `id` (falling
    /// back to name when id is missing).
    private static func dedupedComponents(
        standard: [JiraComponent],
        custom: [JiraComponent]
    ) -> [JiraComponent] {
        var seen = Set<String>()
        var out: [JiraComponent] = []
        for c in standard + custom {
            let key = c.id ?? c.name.lowercased()
            if seen.insert(key).inserted {
                out.append(c)
            }
        }
        return out
    }

    /// Picks the issue's current sprint from whichever field carries it,
    /// preferring the active (then future, then most recent) sprint. Tolerates
    /// the agile `sprint`/`sprints`/`closedSprints` fields and the platform
    /// `customfield_10020` array (objects or legacy greenhopper strings).
    private static func extractSprint(from raw: RawJiraIssue) -> JiraSprint? {
        let fields = raw.fields
        // Agile API populates these top-level fields directly.
        if let s = fields.sprint { return s }
        if let arr = fields.sprints, let s = JiraSprint.current(from: arr) { return s }
        // Platform search/detail: the sprint lives in a tenant-specific custom
        // field, discovered generically by `RawJiraIssue.scanSprints`.
        if let s = JiraSprint.current(from: raw.sprintCandidates) { return s }
        if let arr = fields.closedSprints, let s = JiraSprint.current(from: arr) { return s }
        return nil
    }

    private static func nonEmpty(_ data: Data?) -> Data? {
        guard let data, !data.isEmpty else { return nil }
        return data
    }
}
