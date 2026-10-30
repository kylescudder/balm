import SwiftUI
import XCTest
@testable import BalmFeatures

final class IssueNavigationPolicyTests: XCTestCase {
    func testSelectingAnIssueShowsTheDetailColumnInCompactNavigation() {
        XCTAssertEqual(
            IssueNavigationPolicy.compactColumn(afterSelectingIssue: true),
            .detail
        )
    }

    func testClearingSelectionKeepsTheListVisible() {
        XCTAssertEqual(
            IssueNavigationPolicy.compactColumn(afterSelectingIssue: false),
            .sidebar
        )
    }
}
