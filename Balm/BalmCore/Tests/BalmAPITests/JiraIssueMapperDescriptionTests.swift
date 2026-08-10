import XCTest
import BalmModels
@testable import BalmAPI

/// Regression cover for the instant in-view body filter: list issues carry the
/// description only as ADF, so the mapper must flatten it into `descriptionText`
/// or a search on body text silently matches nothing.
final class JiraIssueMapperDescriptionTests: XCTestCase {
    private func mapFirst(_ json: String) throws -> JiraIssue {
        let page = try JSONDecoder.jira.decode(
            IssueEndpoints.Search.PagedResponse.self,
            from: Data(json.utf8)
        )
        let raw = try XCTUnwrap(page.issues.first)
        return JiraIssueMapper.issue(from: raw)
    }

    func testFlattensADFDescriptionIntoSearchableText() throws {
        let json = """
        {
          "issues": [{
            "id": "1",
            "key": "ABC-1",
            "fields": {
              "summary": "A summary",
              "status": { "name": "To Do", "statusCategory": { "key": "new", "colorName": "blue-gray" } },
              "issuetype": { "name": "Task" },
              "description": {
                "type": "doc",
                "version": 1,
                "content": [
                  { "type": "paragraph", "content": [ { "type": "text", "text": "Payment gateway timeout" } ] }
                ]
              }
            }
          }]
        }
        """
        let issue = try mapFirst(json)
        // The rich ADF is retained for rendering...
        XCTAssertNotNil(issue.descriptionADF)
        // ...and a plain-text projection exists so the body is searchable.
        let text = try XCTUnwrap(issue.descriptionText).lowercased()
        XCTAssertTrue(text.contains("payment gateway timeout"), "got: \(text)")
    }

    func testNullDescriptionLeavesTextAndADFNil() throws {
        let json = """
        {
          "issues": [{
            "id": "2",
            "key": "ABC-2",
            "fields": {
              "summary": "No body",
              "status": { "name": "Done", "statusCategory": { "key": "done", "colorName": "green" } },
              "issuetype": { "name": "Bug" },
              "description": null
            }
          }]
        }
        """
        let issue = try mapFirst(json)
        XCTAssertNil(issue.descriptionADF)
        XCTAssertNil(issue.descriptionText)
    }
}
