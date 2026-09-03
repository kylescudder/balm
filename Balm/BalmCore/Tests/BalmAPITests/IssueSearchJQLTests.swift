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
            #"(issuekey = ABC-123 OR text ~ "abc 123*") order by updated DESC"#
        )
    }

    func testPunctuationIsDroppedSoLuceneCannotChokeOnIt() {
        XCTAssertEqual(
            IssueSearchJQL.make(query: "SAPI >"),
            #"text ~ "SAPI*" order by updated DESC"#
        )
        XCTAssertEqual(
            IssueSearchJQL.make(query: "Odyssey > Job Search > (restore)"),
            #"text ~ "Odyssey Job Search restore*" order by updated DESC"#
        )
        XCTAssertNil(IssueSearchJQL.make(query: ">>> ()"))
    }

    func testSingleCharactersDropOutWhenLongerTermsExist() {
        XCTAssertEqual(
            IssueSearchJQL.make(query: "won't fix"),
            #"text ~ "won fix*" order by updated DESC"#
        )
        XCTAssertEqual(
            IssueSearchJQL.make(query: "x"),
            #"text ~ "x*" order by updated DESC"#
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

    func testQuotesAndBackslashesNeverReachTheQuery() {
        XCTAssertEqual(
            IssueSearchJQL.make(query: #"say "hi" \now"#),
            #"text ~ "say hi now*" order by updated DESC"#
        )
    }
}
