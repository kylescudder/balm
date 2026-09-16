import SwiftUI
import BalmADF
import BalmModels
import BalmDesignSystem

struct ADFContentView: View {
    @Environment(\.balmTheme) private var theme
    let blocks: [ADFBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.m) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                ADFBlockView(block: block)
            }
        }
    }
}

struct ADFBlockView: View {
    @Environment(\.balmTheme) private var theme
    let block: ADFBlock

    var body: some View {
        switch block {
        case .paragraph(let text):
            Text(text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

        case .heading(let level, let text):
            Text(text)
                .font(headingFont(for: level))
                .textSelection(.enabled)
                .padding(.top, theme.spacing.s)

        case .bulletList(let items):
            VStack(alignment: .leading, spacing: theme.spacing.xs) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    listRow(bullet: "•", item: item)
                }
            }

        case .orderedList(let items):
            VStack(alignment: .leading, spacing: theme.spacing.xs) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    listRow(bullet: "\(index + 1).", item: item)
                }
            }

        case .codeBlock(_, let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(theme.typography.bodyMono)
                    .textSelection(.enabled)
                    .padding(theme.spacing.m)
            }
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

        case .quote(let children):
            HStack(spacing: theme.spacing.m) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.tertiary)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: theme.spacing.xs) {
                    ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                        ADFBlockView(block: child)
                    }
                }
            }
            .padding(.leading, theme.spacing.xs)

        case .image(let image):
            ADFInlineImage(image: image)

        case .attachmentRef(_, let filename):
            HStack(spacing: theme.spacing.s) {
                Image(systemName: "paperclip")
                Text(filename ?? "Attachment")
                    .font(theme.typography.body)
            }
            .foregroundStyle(.secondary)
            .padding(theme.spacing.s)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

        case .table(let rows):
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            VStack(alignment: .leading, spacing: theme.spacing.xs) {
                                ForEach(Array(cell.enumerated()), id: \.offset) { _, block in
                                    ADFBlockView(block: block)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(theme.spacing.s)
                            .overlay(Rectangle().stroke(.quaternary, lineWidth: 0.5))
                        }
                    }
                    .background(rowIndex == 0 ? Color.secondary.opacity(0.08) : Color.clear)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
            .clipShape(RoundedRectangle(cornerRadius: 6))

        case .rule:
            Divider()

        case .unknown(let type):
            Text("Unsupported content: \(type)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func listRow(bullet: String, item: [ADFBlock]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.spacing.s) {
            Text(bullet)
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .leading)
            VStack(alignment: .leading, spacing: theme.spacing.xs) {
                ForEach(Array(item.enumerated()), id: \.offset) { _, block in
                    ADFBlockView(block: block)
                }
            }
        }
    }

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1: return theme.typography.title
        case 2: return theme.typography.title2
        case 3: return theme.typography.title3
        default: return theme.typography.headline
        }
    }
}

/// One inline image inside a description or comment.
///
/// A Jira attachment is fetched through the authenticated API (a plain
/// `AsyncImage` gets a 401 from the attachment endpoint) and opens in the
/// full-size viewer on tap. A legacy `image` node with a public URL loads
/// with `AsyncImage` and no credentials.
private struct ADFInlineImage: View {
    @Environment(\.balmTheme) private var theme
    let image: ADFImage

    @State private var viewingAttachment: JiraAttachmentMeta?

    var body: some View {
        Group {
            if let attachment = image.attachment {
                Button {
                    viewingAttachment = attachment
                } label: {
                    JiraImageView(url: image.url, contentMode: .fit) { _ in
                        placeholder
                    }
                }
                .buttonStyle(.plain)
                .help("View \(attachment.filename)")
                .sheet(item: $viewingAttachment) { attachment in
                    ImageViewerSheet(attachment: attachment)
                }
            } else {
                AsyncImage(url: image.url) { phase in
                    switch phase {
                    case .success(let loaded):
                        loaded.resizable().scaledToFit()
                    case .failure:
                        placeholder
                    default:
                        ProgressView().controlSize(.small)
                    }
                }
            }
        }
        .frame(maxWidth: maxWidth, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: theme.radii.md, style: .continuous))
    }

    /// Fill the column, but never stretch a small image past its own pixels.
    private var maxWidth: CGFloat {
        guard let width = image.naturalWidth, width > 0 else { return .infinity }
        return CGFloat(width)
    }

    private var placeholder: some View {
        HStack(spacing: theme.spacing.s) {
            Image(systemName: "photo")
            Text(image.alt ?? "image")
        }
        .padding(theme.spacing.m)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .foregroundStyle(.secondary)
    }
}
