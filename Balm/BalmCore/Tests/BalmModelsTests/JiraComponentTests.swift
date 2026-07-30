import XCTest
@testable import BalmModels

final class JiraComponentTests: XCTestCase {
    private func decode(_ json: String) throws -> JiraComponent {
        try JSONDecoder().decode(JiraComponent.self, from: Data(json.utf8))
    }

    func testDecodesStandardComponentShape() throws {
        let c = try decode(#"{"id":"100","name":"API"}"#)
        XCTAssertEqual(c.id, "100")
        XCTAssertEqual(c.name, "API")
    }

    /// Custom select-field option (e.g. customfield_10312) carries the display
    /// text under `value`, not `name`.
    func testDecodesCustomOptionValueShape() throws {
        let c = try decode(#"{"self":"https://x/customFieldOption/10468","value":"Odyssey Web Client","id":"10468"}"#)
        XCTAssertEqual(c.id, "10468")
        XCTAssertEqual(c.name, "Odyssey Web Client")
    }

    func testRoundTripsViaName() throws {
        let original = JiraComponent(id: "10468", name: "Odyssey Web Client")
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(JiraComponent.self, from: data), original)
    }
}
