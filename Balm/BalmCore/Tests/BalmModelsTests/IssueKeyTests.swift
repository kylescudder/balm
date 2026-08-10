import XCTest
@testable import BalmModels

final class IssueKeyTests: XCTestCase {
    func testFullKeyUppercasesValidShapes() {
        XCTAssertEqual(IssueKey.fullKey("abc-123"), "ABC-123")
        XCTAssertEqual(IssueKey.fullKey("  proj-7 "), "PROJ-7")
        XCTAssertEqual(IssueKey.fullKey("AB1-42"), "AB1-42")
    }

    func testFullKeyRejectsNonKeys() {
        XCTAssertNil(IssueKey.fullKey("123"))
        XCTAssertNil(IssueKey.fullKey("payment bug"))
        XCTAssertNil(IssueKey.fullKey("proj-"))
        XCTAssertNil(IssueKey.fullKey("-123"))
        XCTAssertNil(IssueKey.fullKey("proj 123"))
    }

    func testNormaliseResolvesBareNumberToProject() {
        XCTAssertEqual(IssueKey.normalise("123", projectKey: "ABC"), "ABC-123")
    }

    func testNormalisePassesThroughFullKey() {
        XCTAssertEqual(IssueKey.normalise("xyz-9", projectKey: "ABC"), "XYZ-9")
    }

    func testNormaliseReturnsNilForFreeText() {
        XCTAssertNil(IssueKey.normalise("login screen", projectKey: "ABC"))
        XCTAssertNil(IssueKey.normalise("", projectKey: "ABC"))
    }
}
