import XCTest
@testable import BalmFeatures

final class MultiSelectClearPolicyTests: XCTestCase {
    func testShowsClearActionWhenSelectionContainsOnlyStaleValues() {
        let options = [MultiSelectOption(id: "current", label: "Current")]
        let selection = ["stale"]

        XCTAssertTrue(MultiSelectClearPolicy.shouldShowClearAction(selection: selection, options: options))
    }

    func testHidesClearActionWhenSelectionIsEmpty() {
        let options = [MultiSelectOption(id: "current", label: "Current")]

        XCTAssertFalse(MultiSelectClearPolicy.shouldShowClearAction(selection: [], options: options))
    }
}
