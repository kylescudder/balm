import XCTest
@testable import BalmADF
import BalmModels

final class ADFRendererMediaTests: XCTestCase {
    func testMediaNodeWithMatchingAttachmentRendersAsImage() throws {
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
                    "alt": "diagram.png"
                  }
                }
              ]
            }
          ]
        }
        """.utf8)
        let attachmentURL = try XCTUnwrap(URL(string: "https://jira.example.test/secure/attachment/1/diagram.png"))
        let attachments = [
            JiraAttachmentMeta(
                id: "10001",
                filename: "diagram.png",
                size: 42,
                mimeType: "image/png",
                isImage: true,
                content: attachmentURL,
                mediaFileID: "media-uuid"
            )
        ]

        let blocks = try ADFRenderer().render(json: body, attachments: attachments)

        guard case .image(let url, let alt) = blocks.first else {
            return XCTFail("Expected Jira media attachment to render as inline image, got \(String(describing: blocks.first))")
        }
        XCTAssertEqual(url, attachmentURL)
        XCTAssertEqual(alt, "diagram.png")
    }
}
