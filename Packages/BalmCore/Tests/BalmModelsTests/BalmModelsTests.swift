import XCTest
@testable import BalmModels

final class FilterOptionsTests: XCTestCase {
    func testEmptyHasZeroActive() {
        XCTAssertEqual(FilterOptions.empty.activeCount, 0)
        XCTAssertTrue(FilterOptions.empty.isEmpty)
    }

    func testActiveCountCountsSections() {
        let f = FilterOptions(status: ["To Do"], priority: ["High"], dueDateFrom: "2026-01-01")
        XCTAssertEqual(f.activeCount, 3)
    }
}

final class StatusNormaliserTests: XCTestCase {
    func testNormalisesKnownAliases() {
        XCTAssertEqual(StatusNormaliser.normalise("ToDo"), "To Do")
        XCTAssertEqual(StatusNormaliser.normalise("WONT FIX"), "Not an Issue")
        XCTAssertEqual(StatusNormaliser.normalise("in progress"), "In Progress")
    }

    func testUnknownPassesThrough() {
        XCTAssertEqual(StatusNormaliser.normalise("Quantum Limbo"), "Quantum Limbo")
    }

    func testGroupRankBuckets() {
        XCTAssertEqual(StatusNormaliser.groupRank("To Do"), 0)
        XCTAssertEqual(StatusNormaliser.groupRank("In Progress"), 1)
        XCTAssertEqual(StatusNormaliser.groupRank("Done"), 2)
        XCTAssertEqual(StatusNormaliser.groupRank("Quantum Limbo"), 3)
    }

    func testSemanticTokens() {
        XCTAssertEqual(StatusNormaliser.semanticTokenName("Blocked"), .destructive)
        XCTAssertEqual(StatusNormaliser.semanticTokenName("Done"), .chart5)
        XCTAssertEqual(StatusNormaliser.semanticTokenName("In Progress"), .chart4)
    }
}
