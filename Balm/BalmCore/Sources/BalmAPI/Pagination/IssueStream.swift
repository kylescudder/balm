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
                // Ensure the tenant's Sprint and Instance custom fields are requested
                // (their ids vary per site).
                var effectiveFields = fields
                if let sprintField = await resolveSprintFieldID(),
                   !effectiveFields.contains(sprintField) {
                    effectiveFields.append(sprintField)
                }
                let instanceField = await resolveInstanceFieldID()
                if let instanceField {
                    if !effectiveFields.contains(instanceField) {
                        effectiveFields.append(instanceField)
                    }
                } else {
                    // Field ID unknown — request all fields so the instance value is
                    // present in the response. The field ID will be discovered from
                    // expand=names and cached for subsequent calls.
                    effectiveFields = ["*all"]
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
                        // Discover the instance field ID from expand=names and cache
                        // it so subsequent issueStream calls use the efficient field list.
                        let pageInstanceField: String?
                        if let discovered = page.names?.first(where: {
                            $0.value.localizedCaseInsensitiveContains("Instance")
                        })?.key {
                            seedInstanceFieldID(discovered)
                            pageInstanceField = discovered
                        } else {
                            pageInstanceField = instanceField
                        }
                        let mapped = page.issues.map { JiraIssueMapper.issue(from: $0, instanceFieldID: pageInstanceField) }
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

                if Task.isCancelled {
                    continuation.finish(throwing: CancellationError())
                } else {
                    continuation.finish()
                }
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

    /// Convenience builder: compile JQL from a project + selected sprints + a
    /// `FilterDefinition` (structured tree or raw JQL) and stream issues.
    /// Throws `JiraError.missingSprint` if no sprint is selected (mirrors the web).
    func issues(
        projectKey: String,
        sprints: [String],
        definition: FilterDefinition = .empty,
        componentField: String = "component",
        instanceField: String? = nil
    ) async throws -> [JiraIssue] {
        // Prefer the caller's project-scoped field id (resolved from
        // create-metadata); fall back to the actor's global name scan.
        let resolvedInstanceField: String?
        if let instanceField {
            resolvedInstanceField = instanceField
        } else {
            resolvedInstanceField = await resolveInstanceFieldID()
        }
        let builder = JQLBuilder(
            projectKey: projectKey,
            sprints: sprints,
            definition: definition,
            componentField: componentField,
            instanceFieldID: resolvedInstanceField
        )
        guard let jql = builder.build() else { throw JiraError.missingSprint }
        return try await issues(jql: jql)
    }
}
