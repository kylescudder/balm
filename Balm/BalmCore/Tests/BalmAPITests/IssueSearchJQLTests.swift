import XCTest
import BalmModels
@testable import BalmAPI

final class IssueSearchJQLTests: XCTestCase {
    func testBlankQueryIsNil() {
        XCTAssertNil(IssueSearchJQL.make(query: ""))
        XCTAssertNil(IssueSearchJQL.make(query: "   \n "))
    }

    func testPlainTermMatchesTextWithWildcard() {
        XCTAssertEqual(
            IssueSearchJQL.make(query: "payment failure"),
            #"text ~ "payment failure*" order by updated DESC"#
        )
    }

    func testLeadingAndTrailingWhitespaceIsTrimmed() {
        XCTAssertEqual(
            IssueSearchJQL.make(query: "  login  "),
            #"text ~ "login*" order by updated DESC"#
        )
    }

    func testFullKeyAlsoMatchesIssueKey() {
        XCTAssertEqual(
            IssueSearchJQL.make(query: "abc-123"),
            #"(issuekey = ABC-123 OR text ~ "abc-123*") order by updated DESC"#
        )
    }

    func testBareNumberIsPlainText() {
        // A bare number isn't a full key (no project), so it stays a text search
        // — the view resolves bare numbers to the active project separately.
        XCTAssertEqual(
            IssueSearchJQL.make(query: "123"),
            #"text ~ "123*" order by updated DESC"#
        )
    }

    func testQuotesAndBackslashesAreEscaped() {
        XCTAssertEqual(
            IssueSearchJQL.make(query: #"say "hi" \now"#),
            #"text ~ "say \"hi\" \\now*" order by updated DESC"#
        )
    }
}
