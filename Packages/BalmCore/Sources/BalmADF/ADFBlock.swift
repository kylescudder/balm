import Foundation

/// Rendered block-level output. Inline runs are baked into `AttributedString`s.
/// Render with `ADFBlockView` (in BalmFeatures).
public indirect enum ADFBlock: Sendable {
    case paragraph(AttributedString)
    case heading(level: Int, AttributedString)
    case bulletList([[ADFBlock]])      // each entry is one list item (which can contain blocks)
    case orderedList([[ADFBlock]])
    case codeBlock(language: String?, String)
    case quote([ADFBlock])
    case image(url: URL, alt: String?)
    case attachmentRef(id: String, filename: String?)
    case table([[[ADFBlock]]])         // rows × cells × blocks
    case rule
    case unknown(type: String)
}

public extension AttributedString {
    static let empty = AttributedString("")
}
