import XCTest
@testable import BalmAPI

final class NotificationEndpointsTests: XCTestCase {
    // MARK: - Request construction

    private func queryItems(_ request: URLRequest) -> [URLQueryItem] {
        guard let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return [] }
        return components.queryItems ?? []
    }

    func testMakeRequestURLAndQueryWithoutPageToken() throws {
        let endpoint = NotificationEndpoints.Search(jql: "updated >= -5m", maxResults: 50)
        let request = try endpoint.makeRequest(cloudId: "test")

        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.scheme, "https")
        XCTAssertEqual(request.url?.host, "api.atlassian.com")
        XCTAssertEqual(request.url?.path, "/ex/jira/test/rest/api/3/search/jql")

        let items = Dictionary(uniqueKeysWithValues: queryItems(request).map { ($0.name, $0.value) })
        XCTAssertEqual(items["jql"] ?? nil, "updated >= -5m")
        XCTAssertEqual(items["expand"] ?? nil, "changelog")
        XCTAssertEqual(items["maxResults"] ?? nil, "50")
        XCTAssertEqual(items["fields"] ?? nil, "summary,status,assignee,reporter,created,updated,comment")
        XCTAssertNil(items["nextPageToken"] ?? nil)
    }

    func testMakeRequestIncludesNextPageTokenWhenPresent() throws {
        let endpoint = NotificationEndpoints.Search(jql: "updated >= -5m", nextPageToken: "page-2")
        let request = try endpoint.makeRequest(cloudId: "test")

        let items = Dictionary(uniqueKeysWithValues: queryItems(request).map { ($0.name, $0.value) })
        XCTAssertEqual(items["nextPageToken"] ?? nil, "page-2")
    }

    // MARK: - Response decoding

    func testDecodesRealisticPagedResponse() throws {
        let json = #"""
        {
          "issues": [
            {
              "id": "10001",
              "key": "ABC-1",
              "fields": {
                "summary": "Fix the thing",
                "status": { "name": "In Progress" },
                "assignee": { "accountId": "acc-me", "displayName": "Me" },
                "reporter": { "accountId": "acc-other", "displayName": "Other Person" },
                "created": "2026-07-01T09:00:00.000+0000",
                "updated": "2026-07-16T10:00:00.000+0000",
                "comment": {
                  "comments": [
                    {
                      "id": "9001",
                      "author": { "accountId": "acc-other", "displayName": "Other Person" },
                      "created": "2026-07-16T09:55:00.000+0000",
                      "body": { "type": "doc", "version": 1, "content": [] }
                    },
                    {
                      "id": "9002",
                      "author": { "accountId": "acc-other", "displayName": "Other Person" },
                      "created": "2026-07-16T09:50:00.000+0000",
                      "body": null
                    }
                  ],
                  "total": 2
                }
              },
              "changelog": {
                "histories": [
                  {
                    "id": "8001",
                    "author": { "accountId": "acc-other", "displayName": "Other Person" },
                    "created": "2026-07-16T09:58:00.000+0000",
                    "items": [
                      { "field": "status", "fieldId": "status", "from": "1", "to": "3", "fromString": "To Do", "toString": "In Progress" }
                    ]
                  }
                ],
                "total": 1
              }
            }
          ],
          "nextPageToken": "next-token",
          "isLast": false
        }
        """#

        let response = try JSONDecoder.jira.decode(
            NotificationEndpoints.Search.PagedResponse.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(response.nextPageToken, "next-token")
        XCTAssertEqual(response.isLast, false)
        XCTAssertEqual(response.issues.count, 1)

        let issue = try XCTUnwrap(response.issues.first)
        XCTAssertEqual(issue.id, "10001")
        XCTAssertEqual(issue.key, "ABC-1")
        XCTAssertEqual(issue.fields.summary, "Fix the thing")
        XCTAssertEqual(issue.fields.status?.name, "In Progress")
        XCTAssertEqual(issue.fields.assignee?.accountId, "acc-me")
        XCTAssertEqual(issue.fields.reporter?.displayName, "Other Person")

        let comments = issue.fields.comment?.comments ?? []
        XCTAssertEqual(comments.count, 2)
        XCTAssertFalse(comments[0].body?.rawJSON.isEmpty ?? true)
        // `body` is `ADFEnvelope?` — JSON `null` short-circuits to Swift `nil`
        // before `ADFEnvelope.init(from:)` (and its own object-or-null handling)
        // ever runs, same as the existing `RawJiraComment.body` precedent.
        XCTAssertNil(comments[1].body, "null body decodes to nil, not an empty envelope")

        let histories = issue.changelog?.histories ?? []
        XCTAssertEqual(histories.count, 1)
        let item = try XCTUnwrap(histories.first?.items.first)
        XCTAssertEqual(item.field, "status")
        XCTAssertEqual(item.from, "1")
        XCTAssertEqual(item.to, "3")
        XCTAssertEqual(item.fromString, "To Do")
        XCTAssertEqual(item.toString, "In Progress")
    }

    func testDecodesIssueWithoutChangelogOrComments() throws {
        let json = #"""
        {
          "issues": [
            {
              "id": "10002",
              "key": "ABC-2",
              "fields": {
                "summary": "Untouched issue",
                "status": { "name": "Done" },
                "assignee": null,
                "reporter": { "accountId": "acc-other", "displayName": "Other Person" },
                "created": "2026-07-01T09:00:00.000+0000",
                "updated": "2026-07-10T09:00:00.000+0000",
                "comment": { "comments": [], "total": 0 }
              }
            }
          ],
          "nextPageToken": null,
          "isLast": true
        }
        """#

        let response = try JSONDecoder.jira.decode(
            NotificationEndpoints.Search.PagedResponse.self,
            from: Data(json.utf8)
        )
        XCTAssertNil(response.nextPageToken)
        XCTAssertEqual(response.isLast, true)
        let issue = try XCTUnwrap(response.issues.first)
        XCTAssertNil(issue.fields.assignee)
        XCTAssertNil(issue.changelog)
        XCTAssertEqual(issue.fields.comment?.comments.count, 0)
    }

    // MARK: - Read-state sync

    func testGetReadStateRequestURLAndAccountIdQuery() throws {
        let endpoint = NotificationEndpoints.GetReadState(accountId: "acc-me")
        let request = try endpoint.makeRequest(cloudId: "test")

        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/ex/jira/test/rest/api/3/user/properties/balm-inbox-read-state")

        let items = Dictionary(uniqueKeysWithValues: queryItems(request).map { ($0.name, $0.value) })
        XCTAssertEqual(items["accountId"] ?? nil, "acc-me")
    }

    func testGetReadStateDecodesPropertyEnvelope() throws {
        let json = #"""
        {
          "key": "balm-inbox-read-state",
          "value": { "readIds": ["10001.comment.9001"], "readAllBeforeEpoch": 1752600000, "updatedAtEpoch": 1752600100 }
        }
        """#

        let envelope = try JSONDecoder.jira.decode(
            NotificationEndpoints.GetReadState.PropertyEnvelope.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(envelope.key, "balm-inbox-read-state")
        XCTAssertEqual(envelope.value.readIds, ["10001.comment.9001"])
        XCTAssertEqual(envelope.value.readAllBeforeEpoch, 1752600000)
        XCTAssertEqual(envelope.value.updatedAtEpoch, 1752600100)
    }

    func testPutReadStateRequestMethodBodyAndAccountIdQuery() throws {
        let state = InboxReadState(readIds: ["10001.comment.9001"], readAllBeforeEpoch: 1752600000, updatedAtEpoch: nil)
        let endpoint = NotificationEndpoints.PutReadState(accountId: "acc-me", state: state)
        let request = try endpoint.makeRequest(cloudId: "test")

        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.path, "/ex/jira/test/rest/api/3/user/properties/balm-inbox-read-state")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let items = Dictionary(uniqueKeysWithValues: queryItems(request).map { ($0.name, $0.value) })
        XCTAssertEqual(items["accountId"] ?? nil, "acc-me")

        let body = try XCTUnwrap(request.httpBody)
        let decoded = try JSONDecoder().decode(InboxReadState.self, from: body)
        XCTAssertEqual(decoded, state)
    }
}
