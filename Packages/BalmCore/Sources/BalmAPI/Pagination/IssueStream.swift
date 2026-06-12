import Foundation
import BalmModels

public extension JiraClient {
    /// Streams pages of issues for a given JQL, mapping each page from raw to domain.
    /// Caller consumes via `for try await page in stream`.
    /// Cancellation cancels the underlying task.
    func issueStream(
        jql: String,
        fields: [String] = JiraIssue.defaultFields,
        pageSize: Int = 100
    ) -> AsyncThrowingStream<[JiraIssue], Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                // Ensure the tenant's Sprint custom field is requested (its id
                // varies per site — e.g. customfield_10010 vs _10020).
                var effectiveFields = fields
                if let sprintField = await resolveSprintFieldID(),
                   !effectiveFields.contains(sprintField) {
                    effectiveFields.append(sprintField)
                }
                var token: String? = nil
                repeat {
                    do {
                        let endpoint = IssueEndpoints.Search(
                            jql: jql,
                            fields: effectiveFields,
                            nextPageToken: token,
                            maxResults: pageSize
                        )
                        let page = try await send(endpoint)
                        let mapped = page.issues.map(JiraIssueMapper.issue(from:))
                        continuation.yield(mapped)
                        if let nextToken = page.nextPageToken, page.isLast != true {
                            token = nextToken
                        } else {
                            token = nil
                        }
                    } catch {
                        continuation.finish(throwing: error)
                        return
                    }
                } while token != nil && !Task.isCancelled

                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Convenience that resolves the stream into a single array.
    func issues(jql: String, fields: [String] = JiraIssue.defaultFields) async throws -> [JiraIssue] {
        var all: [JiraIssue] = []
        for try await page in issueStream(jql: jql, fields: fields) {
            all.append(contentsOf: page)
        }
        return all
    }

    /// Convenience builder: build JQL from a project + FilterOptions and stream issues.
    /// Throws `JiraError.missingSprint` if the sprint filter is empty (mirrors the web).
    func issues(projectKey: String, filters: FilterOptions) async throws -> [JiraIssue] {
        let builder = JQLBuilder(projectKey: projectKey, filters: filters)
        guard let jql = builder.build() else { throw JiraError.missingSprint }
        return try await issues(jql: jql)
    }
}
