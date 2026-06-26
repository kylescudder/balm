import XCTest
@testable import BalmAPI

final class IssueFieldPatchTests: XCTestCase {
    private func json(_ value: AnyJSON) throws -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return String(data: try enc.encode(value), encoding: .utf8)!
    }

    // A custom single-select (e.g. MP5's required "Component" field) submits a
    // single `{ "id": … }` object under its custom field id.
    func testOptionFieldSingleSelectUsesIdObject() throws {
        let (key, value) = IssueFieldPatch.optionField(
            "customfield_10312", optionIDs: ["10468"], multiple: false
        )
        XCTAssertEqual(key, "customfield_10312")
        XCTAssertEqual(try json(value), #"{"id":"10468"}"#)
    }

    // A multi-value field (e.g. the system `components` field) submits an array.
    func testOptionFieldMultiSelectUsesArrayOfIdObjects() throws {
        let (key, value) = IssueFieldPatch.optionField(
            "components", optionIDs: ["1", "2"], multiple: true
        )
        XCTAssertEqual(key, "components")
        XCTAssertEqual(try json(value), #"[{"id":"1"},{"id":"2"}]"#)
    }

    func testOptionFieldEmptySingleIsNull() throws {
        let (_, value) = IssueFieldPatch.optionField("f", optionIDs: [], multiple: false)
        XCTAssertEqual(try json(value), "null")
    }

    func testOptionFieldEmptyMultiIsEmptyArray() throws {
        let (_, value) = IssueFieldPatch.optionField("f", optionIDs: [], multiple: true)
        XCTAssertEqual(try json(value), "[]")
    }
}
