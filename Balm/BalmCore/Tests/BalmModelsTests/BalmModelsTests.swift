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

    func testGlyphFillTracksWorkflowProgress() {
        XCTAssertEqual(StatusNormaliser.glyph(for: "To Do").fill, .none)
        XCTAssertEqual(StatusNormaliser.glyph(for: "For Product Prioritisation").fill, .dotted)
        XCTAssertEqual(StatusNormaliser.glyph(for: "In Progress").fill, .half)
        XCTAssertEqual(StatusNormaliser.glyph(for: "PR Review").fill, .threeQuarters)
        XCTAssertEqual(StatusNormaliser.glyph(for: "Awaiting Testing").fill, .threeQuarters)
        XCTAssertEqual(StatusNormaliser.glyph(for: "Done").fill, .full)
    }

    func testGlyphHealthPicksColourFamily() {
        XCTAssertEqual(StatusNormaliser.glyph(for: "Blocked").health, .blocked)
        XCTAssertEqual(StatusNormaliser.glyph(for: "Attention Needed").health, .blocked)
        XCTAssertEqual(StatusNormaliser.glyph(for: "In Review").health, .active)
        XCTAssertEqual(StatusNormaliser.glyph(for: "Awaiting Information").health, .waiting)
        XCTAssertEqual(StatusNormaliser.glyph(for: "Under Monitoring").health, .waiting)
        XCTAssertEqual(StatusNormaliser.glyph(for: "Requires Config Change").health, .done)
        XCTAssertEqual(StatusNormaliser.glyph(for: "Won't Fix").health, .closed)
        XCTAssertEqual(StatusNormaliser.glyph(for: "Quantum Limbo").health, .notStarted)
    }

    func testGlyphMarks() {
        XCTAssertEqual(StatusNormaliser.glyph(for: "Done").mark, .check)
        XCTAssertEqual(StatusNormaliser.glyph(for: "Blocked").mark, .exclamation)
        XCTAssertEqual(StatusNormaliser.glyph(for: "Duplicate").mark, .cross)
        XCTAssertEqual(StatusNormaliser.glyph(for: "In Progress").mark, .none)
    }

    func testHealthDisplayOrderStartsWithToDoAndEndsWithClosed() {
        XCTAssertEqual(StatusHealth.allCases.first, .notStarted)
        XCTAssertEqual(StatusHealth.allCases.last, .closed)
        XCTAssertEqual(StatusHealth.allCases, [.notStarted, .blocked, .active, .waiting, .done, .closed])
    }

    func testPinnedColumnOrderIsTheTeamWorkflow() {
        XCTAssertEqual(StatusNormaliser.pinnedColumnIndex("To Do"), 0)
        XCTAssertEqual(StatusNormaliser.pinnedColumnIndex("backlog"), 0)
        XCTAssertEqual(StatusNormaliser.pinnedColumnIndex("Blocked"), 1)
        XCTAssertEqual(StatusNormaliser.pinnedColumnIndex("needs iteration"), 2)
        XCTAssertEqual(StatusNormaliser.pinnedColumnIndex("In Progress"), 3)
        XCTAssertEqual(StatusNormaliser.pinnedColumnIndex("Current Active Issue"), 4)
        XCTAssertNil(StatusNormaliser.pinnedColumnIndex("In PR"))
        XCTAssertNil(StatusNormaliser.pinnedColumnIndex("Done"))
    }
}
