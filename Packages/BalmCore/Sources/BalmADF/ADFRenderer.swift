import Foundation
import SwiftUI
import BalmModels

public struct ADFRenderer: Sendable {
    public init() {}

    /// Walk an `ADFNode` document and produce a flat list of block-level
    /// `ADFBlock`s ready for SwiftUI rendering. Unknown node types fall through
    /// to `.unknown(type:)` so the view can log + display a placeholder.
    public func render(_ node: ADFNode, attachments: [JiraAttachmentMeta] = []) -> [ADFBlock] {
        let context = Context(attachments: attachments)
        return renderBlocks(node, context: context)
    }

    /// Convenience: render directly from raw ADF JSON bytes.
    public func render(json: Data, attachments: [JiraAttachmentMeta] = []) throws -> [ADFBlock] {
        guard let root = try ADFNode.decode(from: json) else { return [] }
        return render(root, attachments: attachments)
    }

    // MARK: - Internals

    private struct Context {
        let attachments: [JiraAttachmentMeta]
    }

    private func renderBlocks(_ node: ADFNode, context: Context) -> [ADFBlock] {
        switch node.type {
        case "doc":
            return (node.content ?? []).flatMap { renderBlocks($0, context: context) }
        case "paragraph":
            return [renderParagraph(node, context: context)]
        case "heading":
            let level = node.attrs?["level"]?.intValue ?? 1
            return [.heading(level: clamp(level, 1, 6), inlineAttributedString(node.content ?? [], context: context))]
        case "bulletList":
            return [.bulletList(renderListItems(node, context: context))]
        case "orderedList":
            return [.orderedList(renderListItems(node, context: context))]
        case "codeBlock":
            let language = node.attrs?["language"]?.stringValue
            let text = plainText(node.content ?? [])
            return [.codeBlock(language: language, text)]
        case "blockquote":
            let inner = (node.content ?? []).flatMap { renderBlocks($0, context: context) }
            return [.quote(inner)]
        case "rule":
            return [.rule]
        case "hardBreak":
            // Hard breaks rendered standalone become an empty paragraph.
            return [.paragraph(AttributedString("\n"))]
        case "mediaSingle", "mediaGroup":
            return (node.content ?? []).flatMap { renderBlocks($0, context: context) }
        case "media":
            return renderMedia(node, context: context).map { [$0] } ?? []
        case "image":
            return renderImageNode(node).map { [$0] } ?? []
        case "table":
            return [renderTable(node, context: context)]
        case "tableRow", "tableCell", "tableHeader", "tableHeaderCell":
            // Wrapped by parent table — defensive flatten if we land here directly.
            return (node.content ?? []).flatMap { renderBlocks($0, context: context) }
        case "listItem":
            return (node.content ?? []).flatMap { renderBlocks($0, context: context) }
        case "text":
            return [.paragraph(inlineAttributedString([node], context: context))]
        case "mention", "emoji", "date", "status", "panel", "expand", "decisionList", "taskList":
            // Inline-ish nodes that occasionally arrive at block level — render their text.
            return [.paragraph(inlineAttributedString([node], context: context))]
        default:
            return [.unknown(type: node.type)]
        }
    }

    private func renderParagraph(_ node: ADFNode, context: Context) -> ADFBlock {
        .paragraph(inlineAttributedString(node.content ?? [], context: context))
    }

    private func renderListItems(_ node: ADFNode, context: Context) -> [[ADFBlock]] {
        (node.content ?? []).map { child in
            switch child.type {
            case "listItem":
                return (child.content ?? []).flatMap { renderBlocks($0, context: context) }
            default:
                return renderBlocks(child, context: context)
            }
        }
    }

    private func renderTable(_ node: ADFNode, context: Context) -> ADFBlock {
        let rows: [[[ADFBlock]]] = (node.content ?? []).compactMap { row in
            guard row.type == "tableRow" else { return nil }
            let cells: [[ADFBlock]] = (row.content ?? []).compactMap { cell in
                let isCell = cell.type == "tableCell" || cell.type == "tableHeader" || cell.type == "tableHeaderCell"
                guard isCell else { return nil }
                return (cell.content ?? []).flatMap { renderBlocks($0, context: context) }
            }
            return cells.isEmpty ? nil : cells
        }
        return .table(rows)
    }

    private func renderMedia(_ node: ADFNode, context: Context) -> ADFBlock? {
        let alt = node.attrs?["alt"]?.stringValue ?? node.attrs?["title"]?.stringValue

        // Prefer matching to a known attachment by filename, media-services id,
        // or Jira's numeric attachment id. Comment ADF `media.attrs.id` uses the
        // Media Services UUID, not the Jira attachment id.
        if let altName = alt,
           let match = context.attachments.first(where: { $0.filename == altName }),
           let url = match.content {
            return .image(url: url, alt: match.filename)
        }
        if let idAttr = node.attrs?["id"]?.stringValue {
            if let match = context.attachments.first(where: { $0.mediaFileID == idAttr || $0.id == idAttr }) {
                if let url = match.content {
                    return .image(url: url, alt: match.filename)
                }
                return .attachmentRef(id: match.id, filename: match.filename)
            }
            return .attachmentRef(id: idAttr, filename: alt)
        }
        return .attachmentRef(id: "unknown", filename: alt)
    }

    private func renderImageNode(_ node: ADFNode) -> ADFBlock? {
        guard let src = node.attrs?["src"]?.stringValue, let url = URL(string: src) else {
            return nil
        }
        let alt = node.attrs?["alt"]?.stringValue ?? node.attrs?["title"]?.stringValue
        return .image(url: url, alt: alt)
    }

    // MARK: - Inline runs

    private func inlineAttributedString(_ children: [ADFNode], context: Context) -> AttributedString {
        var result = AttributedString("")
        for child in children {
            switch child.type {
            case "text":
                result.append(applyMarks(to: AttributedString(child.text ?? ""), marks: child.marks))
            case "hardBreak":
                result.append(AttributedString("\n"))
            case "mention":
                let text = child.attrs?["text"]?.stringValue ?? "@user"
                var run = AttributedString(text)
                run.foregroundColor = .accentColor
                result.append(run)
            case "emoji":
                let text = child.attrs?["text"]?.stringValue
                    ?? child.attrs?["shortName"]?.stringValue
                    ?? ""
                result.append(AttributedString(text))
            case "inlineCard":
                if let url = child.attrs?["url"]?.stringValue, let u = URL(string: url) {
                    var run = AttributedString(url)
                    run.link = u
                    run.underlineStyle = .single
                    result.append(run)
                }
            default:
                // Some inline-ish children may carry nested content (e.g. status, date).
                if let nested = child.content, !nested.isEmpty {
                    result.append(inlineAttributedString(nested, context: context))
                } else if let txt = child.text {
                    result.append(AttributedString(txt))
                }
            }
        }
        return result
    }

    private func applyMarks(to text: AttributedString, marks: [ADFMark]?) -> AttributedString {
        guard let marks else { return text }
        var attributed = text
        for mark in marks.sorted(by: { Self.markOrder($0.type) < Self.markOrder($1.type) }) {
            switch mark.type {
            case "strong":
                attributed.inlinePresentationIntent = (attributed.inlinePresentationIntent ?? []).union(.stronglyEmphasized)
            case "em":
                attributed.inlinePresentationIntent = (attributed.inlinePresentationIntent ?? []).union(.emphasized)
            case "code":
                attributed.inlinePresentationIntent = (attributed.inlinePresentationIntent ?? []).union(.code)
            case "underline":
                attributed.underlineStyle = .single
            case "strike", "strikeout", "strikethrough":
                attributed.strikethroughStyle = .single
            case "link":
                if let href = mark.attrs?["href"]?.stringValue, let url = URL(string: href) {
                    attributed.link = url
                    attributed.underlineStyle = .single
                }
            case "textColor":
                if let hex = mark.attrs?["color"]?.stringValue, let color = Color(adfHex: hex) {
                    attributed.foregroundColor = color
                }
            case "backgroundColor":
                if let hex = mark.attrs?["color"]?.stringValue, let color = Color(adfHex: hex) {
                    attributed.backgroundColor = color
                }
            default:
                continue
            }
        }
        return attributed
    }

    private static func markOrder(_ type: String) -> Int {
        switch type {
        case "link": return 1
        case "code": return 2
        case "strong": return 3
        case "em": return 4
        case "underline": return 5
        case "strike", "strikeout", "strikethrough": return 6
        case "textColor": return 7
        case "backgroundColor": return 8
        default: return 99
        }
    }

    // MARK: - Plain text extraction (for code blocks)

    private func plainText(_ nodes: [ADFNode]) -> String {
        nodes.map { n -> String in
            if n.type == "text" { return n.text ?? "" }
            if n.type == "hardBreak" { return "\n" }
            return plainText(n.content ?? [])
        }.joined()
    }

    private func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int { min(max(v, lo), hi) }
}

private extension Color {
    /// Parses an ADF `#rrggbb` (or `#rgb`) colour string.
    init?(adfHex hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces).lowercased()
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        self.init(
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255
        )
    }
}
