import XCTest
@testable import BalmAPI

final class InboxReadStateTests: XCTestCase {
    private func date(epoch: Double) -> Date {
        Date(timeIntervalSince1970: epoch)
    }

    // MARK: - union

    func testUnionCombinesReadIdsPreservingAOrderThenBNovelIds() {
        let a = InboxReadState(readIds: ["1", "2"])
        let b = InboxReadState(readIds: ["2", "3"])

        let merged = InboxReadState.union(a, b)

        XCTAssertEqual(merged.readIds, ["1", "2", "3"])
    }

    func testUnionIsCommutativeInEffect() {
        let a = InboxReadState(readIds: ["1", "2"], readAllBeforeEpoch: 100)
        let b = InboxReadState(readIds: ["2", "3"], readAllBeforeEpoch: 200)

        let ab = InboxReadState.union(a, b)
        let ba = InboxReadState.union(b, a)

        XCTAssertEqual(Set(ab.readIds), Set(ba.readIds))
        XCTAssertEqual(ab.readAllBeforeEpoch, ba.readAllBeforeEpoch)
    }

    func testUnionIsIdempotent() {
        let a = InboxReadState(readIds: ["1", "2"], readAllBeforeEpoch: 100, updatedAtEpoch: 150)

        let merged = InboxReadState.union(a, a)

        XCTAssertEqual(merged, a)
    }

    func testUnionTakesMaxOfReadAllBeforeEpoch() {
        let a = InboxReadState(readAllBeforeEpoch: 100)
        let b = InboxReadState(readAllBeforeEpoch: 200)

        XCTAssertEqual(InboxReadState.union(a, b).readAllBeforeEpoch, 200)
        XCTAssertEqual(InboxReadState.union(b, a).readAllBeforeEpoch, 200)
    }

    func testUnionTreatsNilEpochAsAbsentNotZero() {
        let a = InboxReadState(readAllBeforeEpoch: nil)
        let b = InboxReadState(readAllBeforeEpoch: 200)

        XCTAssertEqual(InboxReadState.union(a, b).readAllBeforeEpoch, 200)
        XCTAssertNil(InboxReadState.union(InboxReadState(), InboxReadState()).readAllBeforeEpoch)
    }

    func testUnionTakesMaxOfUpdatedAtEpoch() {
        let a = InboxReadState(updatedAtEpoch: 10)
        let b = InboxReadState(updatedAtEpoch: 20)

        XCTAssertEqual(InboxReadState.union(a, b).updatedAtEpoch, 20)
    }

    func testUnionCapsMergedReadIdsAt500DroppingOldest() {
        // `a` already holds the full 500; `b` contributes one more novel id —
        // the oldest entry in `a` should be the one dropped, not `b`'s.
        let existing = (0..<500).map { "a.\($0)" }
        let a = InboxReadState(readIds: existing)
        let b = InboxReadState(readIds: ["novel"])

        let merged = InboxReadState.union(a, b)

        XCTAssertEqual(merged.readIds.count, InboxReadState.readIdsCap)
        XCTAssertEqual(merged.readIds.last, "novel")
        XCTAssertEqual(merged.readIds.first, "a.1", "oldest entry dropped to make room")
    }

    // MARK: - isRead

    func testIsReadTrueWhenIdInReadIds() {
        let state = InboxReadState(readIds: ["abc"])
        XCTAssertTrue(state.isRead(id: "abc", date: date(epoch: 0)))
    }

    func testIsReadTrueWhenDateAtOrBeforeEpoch() {
        let state = InboxReadState(readAllBeforeEpoch: 1000)
        XCTAssertTrue(state.isRead(id: "unseen", date: date(epoch: 1000)))
        XCTAssertTrue(state.isRead(id: "unseen", date: date(epoch: 500)))
    }

    func testIsReadFalseWhenNeitherIdNorEpochMatch() {
        let state = InboxReadState(readIds: ["other"], readAllBeforeEpoch: 1000)
        XCTAssertFalse(state.isRead(id: "unseen", date: date(epoch: 1001)))
    }

    // MARK: - markRead / markUnread

    func testMarkReadAddsIdOnce() {
        var state = InboxReadState()
        state.markRead(id: "abc")
        state.markRead(id: "abc")

        XCTAssertEqual(state.readIds, ["abc"])
    }

    func testMarkUnreadRemovesId() {
        var state = InboxReadState(readIds: ["abc", "def"])
        state.markUnread(id: "abc")

        XCTAssertEqual(state.readIds, ["def"])
    }

    func testMarkUnreadOfMissingIdIsNoOp() {
        var state = InboxReadState(readIds: ["abc"])
        state.markUnread(id: "missing")

        XCTAssertEqual(state.readIds, ["abc"])
    }

    func testMarkReadThenMarkUnreadRoundTrips() {
        var state = InboxReadState()
        state.markRead(id: "abc")
        XCTAssertTrue(state.isRead(id: "abc", date: date(epoch: 0)))

        state.markUnread(id: "abc")
        XCTAssertFalse(state.isRead(id: "abc", date: date(epoch: 0)))
    }

    func testMarkReadBumpsUpdatedAtEpoch() {
        var state = InboxReadState()
        XCTAssertNil(state.updatedAtEpoch)

        state.markRead(id: "abc")

        XCTAssertNotNil(state.updatedAtEpoch)
    }

    func testMarkReadRecapsAt500DroppingOldest() {
        var state = InboxReadState(readIds: (0..<500).map { "seed.\($0)" })
        state.markRead(id: "new")

        XCTAssertEqual(state.readIds.count, InboxReadState.readIdsCap)
        XCTAssertEqual(state.readIds.last, "new")
        XCTAssertEqual(state.readIds.first, "seed.1")
    }

    // MARK: - markAllRead

    func testMarkAllReadClearsReadIdsAndSetsEpoch() {
        var state = InboxReadState(readIds: ["abc", "def"])
        let asOf = date(epoch: 5000)

        state.markAllRead(asOf: asOf)

        XCTAssertEqual(state.readIds, [])
        XCTAssertEqual(state.readAllBeforeEpoch, 5000)
    }

    func testMarkAllReadNeverLowersAnExistingEpoch() {
        var state = InboxReadState(readAllBeforeEpoch: 5000)

        state.markAllRead(asOf: date(epoch: 1000))

        XCTAssertEqual(state.readAllBeforeEpoch, 5000, "an earlier asOf must not regress the epoch")
    }

    func testMarkAllReadAdvancesALowerEpochForward() {
        var state = InboxReadState(readAllBeforeEpoch: 1000)

        state.markAllRead(asOf: date(epoch: 5000))

        XCTAssertEqual(state.readAllBeforeEpoch, 5000)
    }

    func testMarkAllReadCoversPreviouslyMarkedIdsViaEpoch() {
        var state = InboxReadState(readIds: ["abc"])
        state.markAllRead(asOf: date(epoch: 5000))

        // `readIds` was cleared, but anything at/before the new epoch still
        // reads as read.
        XCTAssertTrue(state.isRead(id: "abc", date: date(epoch: 100)))
        XCTAssertTrue(state.isRead(id: "anything-else", date: date(epoch: 5000)))
        XCTAssertFalse(state.isRead(id: "anything-else", date: date(epoch: 5001)))
    }

    // MARK: - Codable

    func testCodableRoundTrip() throws {
        let state = InboxReadState(readIds: ["a", "b"], readAllBeforeEpoch: 123.5, updatedAtEpoch: 456.75)

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(InboxReadState.self, from: data)

        XCTAssertEqual(decoded, state)
    }

    func testCodableRoundTripWithNilOptionals() throws {
        let state = InboxReadState()

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(InboxReadState.self, from: data)

        XCTAssertEqual(decoded, state)
    }

    func testDecodesFromMinimalJSON() throws {
        let json = #"{"readIds": ["x"]}"#
        let decoded = try JSONDecoder().decode(InboxReadState.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.readIds, ["x"])
        XCTAssertNil(decoded.readAllBeforeEpoch)
        XCTAssertNil(decoded.updatedAtEpoch)
    }
}
