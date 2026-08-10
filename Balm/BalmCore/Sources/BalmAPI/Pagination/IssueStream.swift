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
                let (effectiveFields, fallbackInstanceField) = await searchFields(base: fields)
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
                        continuation.yield(mapSearchPage(page, fallbackInstanceField: fallbackInstanceField))
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

    /// Global, instance-wide free-text search matching title, body, comments and
    /// an exact issue key — see `IssueSearchJQL`. Unlike `issues(jql:)` this
    /// fetches only the first page (capped at `limit`), because an unscoped
    /// search can match thousands of issues and the caller only shows a handful.
    /// Returns `[]` for a blank query.
    func searchIssues(matching query: String, limit: Int = 50) async throws -> [JiraIssue] {
        guard let jql = IssueSearchJQL.make(query: query) else { return [] }
        let (effectiveFields, fallbackInstanceField) = await searchFields(base: JiraIssue.defaultFields)
        let page = try await send(IssueEndpoints.Search(jql: jql, fields: effectiveFields, maxResults: limit))
        return mapSearchPage(page, fallbackInstanceField: fallbackInstanceField)
    }
}

extension JiraClient {
    /// Resolve the field list to request for a search: the caller's `base` plus
    /// this tenant's Sprint and Instance custom-field ids. When the Instance
    /// field id isn't known yet, fall back to `*all` so its value is present in
    /// the response (the id is then discovered from `expand=names` and cached).
    /// Returns the fields to request and the resolved instance field id (if any).
    func searchFields(base: [String]) async -> (fields: [String], instanceField: String?) {
        var effectiveFields = base
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
            effectiveFields = ["*all"]
        }
        return (effectiveFields, instanceField)
    }

    /// Map a search page to domain issues, discovering and caching the Instance
    /// field id from `expand=names` when it wasn't known up front.
    func mapSearchPage(
        _ page: IssueEndpoints.Search.PagedResponse,
        fallbackInstanceField: String?
    ) -> [JiraIssue] {
        let pageInstanceField: String?
        if let discovered = page.names?.first(where: {
            $0.value.localizedCaseInsensitiveContains("Instance")
        })?.key {
            seedInstanceFieldID(discovered)
            pageInstanceField = discovered
        } else {
            pageInstanceField = fallbackInstanceField
        }
        return page.issues.map { JiraIssueMapper.issue(from: $0, instanceFieldID: pageInstanceField) }
    }
}
