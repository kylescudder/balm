import SwiftUI
import BalmModels
import BalmADF
import BalmDesignSystem
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

struct CommentListView: View {
    @Environment(\.balmTheme) private var theme
    @Environment(AppEnvironment.self) private var env
    @Bindable var model: IssueDetailViewModel
    private let renderer = ADFRenderer()

    @State private var draft = NSAttributedString(string: "")
    @State private var pendingDelete: JiraComment?
    @State private var isDropTargeted = false

    // @mention autocomplete state
    @State private var mentionQuery: MentionQuery?
    @State private var mentionResults: [JiraUser] = []
    @State private var highlightedIndex = 0
    @State private var mentionSearchTask: Task<Void, Never>?
    @StateObject private var mentionController = MentionController()

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.l) {
            SectionHeading("Comments (\(model.details.comments.count))")
            if model.details.comments.isEmpty {
                Text("No comments yet.")
                    .font(theme.typography.callout)
                    .foregroundStyle(theme.palette.mutedForeground)
            } else {
                ForEach(model.details.comments) { comment in
                    CommentRow(
                        comment: comment,
                        renderer: renderer,
                        linkURL: commentLinkURL(for: comment),
                        onEdit: { newText in
                            Task { await model.editComment(id: comment.id, plainText: newText) }
                        },
                        onDelete: { pendingDelete = comment }
                    )
                    if comment.id != model.details.comments.last?.id {
                        Divider().background(theme.palette.border)
                    }
                }
            }
            composer
        }
        .confirmationDialog(
            "Delete this comment?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { comment in
            Button("Delete", role: .destructive) {
                Task { await model.deleteComment(id: comment.id) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { _ in
            Text("This can't be undone.")
        }
    }

    private var composer: some View {
        VStack(alignment: .trailing, spacing: theme.spacing.s) {
            editorBox

            HStack {
                if canPost {
                    Button("Clear", role: .destructive) {
                        resetComposer()
                    }
                    .buttonStyle(.borderless)
                }
                Spacer()
                Button {
                    pasteImageFromClipboard()
                } label: {
                    Label("Paste image", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.borderless)
                .help("Paste an image from the clipboard — or just ⌘V / drag one in")
                Button("Post Comment") { postComment() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canPost)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("Post comment — ⌘↩")
            }
        }
    }

    /// The text field plus the caret-anchored mention dropdown overlaid on top.
    private var editorBox: some View {
        MentionTextView(
            text: $draft,
            controller: mentionController,
            suggestionsActive: suggestionsActive,
            onQueryChange: handleQueryChange,
            onMoveSelection: moveHighlight,
            highlightedUser: { mentionResults.indices.contains(highlightedIndex) ? mentionResults[highlightedIndex] : nil },
            onCancel: dismissMentions
        )
        .frame(height: 88)
        .padding(theme.spacing.xs)
        .background(theme.palette.card)
        .overlay(
            RoundedRectangle(cornerRadius: theme.radii.md, style: .continuous)
                .strokeBorder(isDropTargeted ? theme.palette.accent : theme.palette.border,
                              lineWidth: isDropTargeted ? 2 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: theme.radii.md, style: .continuous))
        .overlay(alignment: .topLeading) {
            if suggestionsActive, let anchor = mentionQuery?.anchor {
                mentionSuggestions
                    .offset(x: anchor.minX, y: anchor.maxY + 4)
            }
        }
        .onDrop(of: [.image, .fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
    }

    private var mentionSuggestions: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(mentionResults.enumerated()), id: \.element.id) { index, user in
                HStack(spacing: theme.spacing.s) {
                    AvatarView(name: user.displayName, avatarURL: user.avatarUrls?.bestAvailable, size: 22)
                    Text(user.displayName)
                        .font(theme.typography.body)
                        .foregroundStyle(theme.palette.foreground)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, theme.spacing.s)
                .padding(.vertical, 5)
                .background(index == highlightedIndex ? theme.palette.accent.opacity(0.18) : .clear)
                .contentShape(Rectangle())
                .onTapGesture { mentionController.insert(user) }
            }
        }
        .frame(width: 260, alignment: .leading)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: theme.radii.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: theme.radii.md, style: .continuous)
                .strokeBorder(theme.palette.border)
        )
        .shadow(radius: 10, y: 4)
    }

    private var suggestionsActive: Bool {
        mentionQuery != nil && !mentionResults.isEmpty
    }

    private var canPost: Bool {
        !draftIsEmpty(draft)
    }

    /// Permalink to a specific comment: `<site>/browse/<KEY>?focusedCommentId=<id>`.
    /// Nil for optimistic (not-yet-posted) comments or when signed out.
    private func commentLinkURL(for comment: JiraComment) -> URL? {
        guard !comment.id.hasPrefix("tmp-") else { return nil }
        guard case .signedIn(_, let siteURL, _) = env.authState else { return nil }
        let base = siteURL.appendingPathComponent("browse").appendingPathComponent(model.issueKey)
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "focusedCommentId", value: comment.id)]
        return components?.url
    }

    private func postComment() {
        guard canPost else { return }
        let segments = draftSegments(from: draft)
        resetComposer()
        Task { await model.addComment(draft: segments) }
    }

    private func resetComposer() {
        draft = NSAttributedString(string: "")
        dismissMentions()
    }

    private func dismissMentions() {
        mentionSearchTask?.cancel()
        mentionQuery = nil
        mentionResults = []
        highlightedIndex = 0
    }

    private func handleQueryChange(_ query: MentionQuery?) {
        mentionQuery = query
        guard let query else { dismissMentions(); return }
        scheduleMentionSearch(query.text)
    }

    private func moveHighlight(_ delta: Int) {
        guard !mentionResults.isEmpty else { return }
        let count = mentionResults.count
        highlightedIndex = (highlightedIndex + delta + count) % count
    }

    private func scheduleMentionSearch(_ query: String) {
        mentionSearchTask?.cancel()
        mentionSearchTask = Task {
            try? await Task.sleep(for: .milliseconds(180))
            if Task.isCancelled { return }
            let users = await model.searchMentionUsers(query: query)
            if Task.isCancelled { return }
            mentionResults = users
            highlightedIndex = 0
        }
    }

    /// Paste-image button: grab a clipboard image and drop it inline at the
    /// caret. (⌘V in the editor does this directly too; this is the discoverable
    /// affordance.) Toasts when there's nothing image-shaped to paste.
    private func pasteImageFromClipboard() {
        if let image = clipboardPastedImage() {
            mentionController.insert(image: image)
        } else {
            model.toaster?.info("No image on the clipboard")
        }
    }

    /// Accept images dropped onto the composer (raw image data or image files)
    /// and insert each inline.
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                handled = true
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data else { return }
                    let image = IssueDetailViewModel.PastedImage(
                        data: data,
                        filename: "dropped-\(UUID().uuidString.prefix(8)).png",
                        mimeType: "image/png"
                    )
                    Task { @MainActor in mentionController.insert(image: image) }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, let data = try? Data(contentsOf: url) else { return }
                    let ext = url.pathExtension.lowercased()
                    let image = IssueDetailViewModel.PastedImage(
                        data: data,
                        filename: url.lastPathComponent,
                        mimeType: "image/\(ext == "jpg" ? "jpeg" : (ext.isEmpty ? "png" : ext))"
                    )
                    Task { @MainActor in mentionController.insert(image: image) }
                }
            }
        }
        return handled
    }
}

private struct CommentRow: View {
    @Environment(\.balmTheme) private var theme
    let comment: JiraComment
    let renderer: ADFRenderer
    let linkURL: URL?
    let onEdit: (String) -> Void
    let onDelete: () -> Void

    @State private var isEditing = false
    @State private var draftBody: String = ""
    @State private var isHovering = false
    @State private var copiedLink = false

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s) {
            HStack(spacing: theme.spacing.s) {
                AvatarView(name: comment.author.displayName, avatarURL: comment.author.avatarURL, size: 28)
                VStack(alignment: .leading, spacing: 0) {
                    Text(comment.author.displayName)
                        .font(theme.typography.body.weight(.semibold))
                        .foregroundStyle(theme.palette.foreground)
                    Text(timestampLabel)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.palette.mutedForeground)
                }
                Spacer()
                if !isEditing && !isOptimistic {
                    copyLinkButton
                    actionsMenu
                }
            }

            if isEditing {
                editor
            } else {
                bodyView
            }
        }
        .opacity(isOptimistic ? 0.65 : 1.0)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovering)
        .animation(.easeInOut(duration: 0.12), value: copiedLink)
    }

    /// Hover-revealed permalink copy, mirroring the key-badge button. Stays
    /// visible briefly after a copy to show the confirmation tick.
    @ViewBuilder
    private var copyLinkButton: some View {
        if let linkURL {
            Button { copyLink(linkURL) } label: {
                Image(systemName: copiedLink ? "checkmark" : "link")
                    .font(.caption2)
                    .foregroundStyle(copiedLink ? AnyShapeStyle(.green) : AnyShapeStyle(theme.palette.mutedForeground))
            }
            .buttonStyle(.plain)
            .help("Copy link to this comment")
            .opacity(showCopyLink ? 1 : 0)
        }
    }

    private var showCopyLink: Bool {
        #if os(macOS)
        return isHovering || copiedLink
        #else
        return true
        #endif
    }

    private func copyLink(_ url: URL) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        #elseif canImport(UIKit)
        UIPasteboard.general.string = url.absoluteString
        #endif
        copiedLink = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            copiedLink = false
        }
    }

    private var actionsMenu: some View {
        Menu {
            Button("Edit", systemImage: "pencil") {
                draftBody = comment.body
                isEditing = true
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
                onDelete()
            }
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(theme.palette.mutedForeground)
                .padding(.horizontal, theme.spacing.xs)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private var bodyView: some View {
        if let adf = comment.bodyADF, let blocks = try? renderer.render(json: adf) {
            ADFContentView(blocks: blocks)
        } else if !comment.body.isEmpty {
            Text(comment.body)
                .font(theme.typography.body)
                .foregroundStyle(theme.palette.foreground)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("(empty)")
                .font(theme.typography.caption)
                .foregroundStyle(theme.palette.mutedForeground)
        }
    }

    private var editor: some View {
        VStack(alignment: .trailing, spacing: theme.spacing.s) {
            TextEditor(text: $draftBody)
                .font(theme.typography.body)
                .frame(height: 96)
                .padding(theme.spacing.s)
                .overlay(
                    RoundedRectangle(cornerRadius: theme.radii.md, style: .continuous)
                        .strokeBorder(theme.palette.border)
                )
                .clipShape(RoundedRectangle(cornerRadius: theme.radii.md, style: .continuous))
            HStack {
                Button("Cancel", role: .cancel) { isEditing = false }
                    .buttonStyle(.borderless)
                Spacer()
                Button("Save") {
                    onEdit(draftBody)
                    isEditing = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || draftBody == comment.body
                )
            }
        }
    }

    private var isOptimistic: Bool { comment.id.hasPrefix("tmp-") }

    private var timestampLabel: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        guard let created = comment.created else { return "" }
        if isOptimistic { return "Posting…" }
        let stamp = formatter.localizedString(for: created, relativeTo: Date())
        let edited: Bool = {
            guard let updated = comment.updated else { return false }
            return updated.timeIntervalSince(created) > 1.0
        }()
        return edited ? "\(stamp) · edited" : stamp
    }
}
