import XCTest
@testable import BalmAPI
import BalmModels

final class CommentEndpointsTests: XCTestCase {
    func testSegmentImageCarriesPixelDimensions() throws {
        let endpoint = IssueEndpoints.AddComment(
            issueKey: "PRJ-1",
            segments: [
                .text("before"),
                .image(mediaFileID: "media-uuid", width: 1440, height: 900),
            ]
        )
        let media = try mediaAttrs(from: endpoint)

        XCTAssertEqual(media["type"] as? String, "file")
        XCTAssertEqual(media["id"] as? String, "media-uuid")
        XCTAssertEqual(media["width"] as? Int, 1440)
        XCTAssertEqual(media["height"] as? Int, 900)
    }

    func testSegmentImageWithoutDimensionsOmitsAttrs() throws {
        let endpoint = IssueEndpoints.AddComment(
            issueKey: "PRJ-1",
            segments: [.image(mediaFileID: "media-uuid", width: nil, height: nil)]
        )
        let media = try mediaAttrs(from: endpoint)

        XCTAssertEqual(media["id"] as? String, "media-uuid")
        XCTAssertNil(media["width"])
        XCTAssertNil(media["height"])
    }

    /// Digs the first `media` node's attrs out of the encoded request body.
    private func mediaAttrs(from endpoint: IssueEndpoints.AddComment) throws -> [String: Any] {
        let request = try endpoint.makeRequest(cloudId: "test")
        let body = try XCTUnwrap(request.httpBody)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let doc = try XCTUnwrap(root["body"] as? [String: Any])
        let blocks = try XCTUnwrap(doc["content"] as? [[String: Any]])
        let mediaSingle = try XCTUnwrap(blocks.first { $0["type"] as? String == "mediaSingle" })
        let children = try XCTUnwrap(mediaSingle["content"] as? [[String: Any]])
        let media = try XCTUnwrap(children.first { $0["type"] as? String == "media" })
        return try XCTUnwrap(media["attrs"] as? [String: Any])
    }
}
