import SwiftUI
import BalmADF
import BalmDesignSystem

struct ADFContentView: View {
    @Environment(\.balmTheme) private var theme
    let blocks: [ADFBlock]
    var loadsImagesWithJiraAuth = false

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.m) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                ADFBlockView(block: block, loadsImagesWithJiraAuth: loadsImagesWithJiraAuth)
            }
        }
    }
}

struct ADFBlockView: View {
    @Environment(\.balmTheme) private var theme
    let block: ADFBlock
    var loadsImagesWithJiraAuth = false

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
                        ADFBlockView(block: child, loadsImagesWithJiraAuth: loadsImagesWithJiraAuth)
                    }
                }
            }
            .padding(.leading, theme.spacing.xs)

        case .image(let url, let alt):
            Group {
                if loadsImagesWithJiraAuth {
                    JiraImageView(url: url, contentMode: .fit) { _ in
                        placeholderImage(alt: alt ?? "image")
                    }
                } else {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFit()
                        case .failure:
                            placeholderImage(alt: alt ?? "image")
                        default:
                            ProgressView()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: theme.radii.md, style: .continuous))

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
                                    ADFBlockView(block: block, loadsImagesWithJiraAuth: loadsImagesWithJiraAuth)
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
                    ADFBlockView(block: block, loadsImagesWithJiraAuth: loadsImagesWithJiraAuth)
                }
            }
        }
    }

    @ViewBuilder
    private func placeholderImage(alt: String) -> some View {
        HStack(spacing: theme.spacing.s) {
            Image(systemName: "photo")
            Text(alt)
        }
        .padding(theme.spacing.m)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .foregroundStyle(.secondary)
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
