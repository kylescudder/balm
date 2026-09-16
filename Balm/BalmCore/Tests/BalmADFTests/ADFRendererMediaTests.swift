import XCTest
@testable import BalmADF
import BalmModels

final class ADFRendererMediaTests: XCTestCase {
    func testMediaNodeWithMatchingAttachmentRendersAsAuthenticatedImage() throws {
        let body = Data("""
        {
          "type": "doc",
          "version": 1,
          "content": [
            {
              "type": "mediaSingle",
              "content": [
                {
                  "type": "media",
                  "attrs": {
                    "id": "media-uuid",
                    "type": "file",
                    "alt": "diagram.png",
                    "width": 1440,
                    "height": 900
                  }
                }
              ]
            }
          ]
        }
        """.utf8)
        let attachmentURL = try XCTUnwrap(URL(string: "https://jira.example.test/secure/attachment/1/diagram.png"))
        let attachment = JiraAttachmentMeta(
            id: "10001",
            filename: "diagram.png",
            size: 42,
            mimeType: "image/png",
            isImage: true,
            content: attachmentURL,
            mediaFileID: "media-uuid"
        )

        let blocks = try ADFRenderer().render(json: body, attachments: [attachment])

        guard case .image(let image) = blocks.first else {
            return XCTFail("Expected Jira media attachment to render as inline image, got \(String(describing: blocks.first))")
        }
        XCTAssertEqual(image.url, attachmentURL)
        XCTAssertEqual(image.alt, "diagram.png")
        XCTAssertEqual(image.attachment, attachment, "The view needs the attachment to fetch bytes with Jira auth")
        XCTAssertEqual(image.naturalWidth, 1440)
    }

    func testMediaNodeWithoutAltMatchesByMediaFileID() throws {
        let body = Data("""
        {
          "type": "doc",
          "version": 1,
          "content": [
            {
              "type": "mediaSingle",
              "attrs": { "layout": "center" },
              "content": [
                {
                  "type": "media",
                  "attrs": { "id": "media-uuid", "type": "file", "collection": "" }
                }
              ]
            }
          ]
        }
        """.utf8)
        let attachmentURL = try XCTUnwrap(URL(string: "https://jira.example.test/secure/attachment/2/shot.png"))
        let attachment = JiraAttachmentMeta(
            id: "10002",
            filename: "shot.png",
            size: 1,
            mimeType: "image/png",
            isImage: true,
            content: attachmentURL,
            mediaFileID: "media-uuid"
        )

        let blocks = try ADFRenderer().render(json: body, attachments: [attachment])

        guard case .image(let image) = blocks.first else {
            return XCTFail("Expected media matched by file id to render as image, got \(String(describing: blocks.first))")
        }
        XCTAssertEqual(image.url, attachmentURL)
        XCTAssertEqual(image.attachment, attachment)
        XCTAssertNil(image.naturalWidth)
    }

    func testMediaNodeWithNoMatchingAttachmentFallsBackToReference() throws {
        let body = Data("""
        {
          "type": "doc",
          "version": 1,
          "content": [
            {
              "type": "mediaSingle",
              "content": [
                { "type": "media", "attrs": { "id": "unknown-uuid", "type": "file", "alt": "gone.png" } }
              ]
            }
          ]
        }
        """.utf8)

        let blocks = try ADFRenderer().render(json: body, attachments: [])

        guard case .attachmentRef(let id, let filename) = blocks.first else {
            return XCTFail("Expected unmatched media to render as a reference, got \(String(describing: blocks.first))")
        }
        XCTAssertEqual(id, "unknown-uuid")
        XCTAssertEqual(filename, "gone.png")
    }

    func testLegacyImageNodeRendersAsPublicImage() throws {
        let body = Data("""
        {
          "type": "doc",
          "version": 1,
          "content": [
            { "type": "image", "attrs": { "src": "https://cdn.example.test/pic.png", "alt": "A picture" } }
          ]
        }
        """.utf8)

        let blocks = try ADFRenderer().render(json: body, attachments: [])

        guard case .image(let image) = blocks.first else {
            return XCTFail("Expected legacy image node to render as image, got \(String(describing: blocks.first))")
        }
        XCTAssertEqual(image.url.absoluteString, "https://cdn.example.test/pic.png")
        XCTAssertEqual(image.alt, "A picture")
        XCTAssertNil(image.attachment, "Public URLs must not be routed through the Jira gateway")
    }
}
