import SwiftUI
import QuickLook
import UniformTypeIdentifiers
import BalmModels
import BalmAPI
import BalmDesignSystem

#if canImport(PhotosUI)
import PhotosUI
#endif

struct AttachmentListView: View {
    @Environment(\.balmTheme) private var theme
    @Environment(AppEnvironment.self) private var env
    @Bindable var model: IssueDetailViewModel

    @State private var showingFileImporter = false
    @State private var pendingDelete: JiraAttachmentMeta?
    @State private var previewURL: URL?
    @State private var viewingImage: JiraAttachmentMeta?
    @State private var isPreparingPreview = false
    @State private var isDropTargeted = false

    #if !os(macOS)
    @State private var photoSelection: [PhotosPickerItem] = []
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.m) {
            header
            content
        }
        .padding(theme.spacing.s)
        .background(
            RoundedRectangle(cornerRadius: theme.radii.lg)
                .strokeBorder(
                    isDropTargeted ? theme.palette.primary : Color.clear,
                    style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                )
        )
        .dropDestination(for: URL.self) { urls, _ in
            for url in urls {
                Task { await model.uploadAttachment(fileURL: url) }
            }
            return !urls.isEmpty
        } isTargeted: { isDropTargeted = $0 }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                for url in urls {
                    Task { await model.uploadAttachment(fileURL: url) }
                }
            case .failure(let error):
                env.toaster.error("Couldn't open file: \(error.localizedDescription)")
            }
        }
        .confirmationDialog(
            "Delete this attachment?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { att in
            Button("Delete", role: .destructive) {
                Task { await model.deleteAttachment(id: att.id) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { att in
            Text(att.filename)
        }
        .quickLookPreview($previewURL)
        .sheet(item: $viewingImage) { att in
            ImageViewerSheet(attachment: att)
        }
        #if !os(macOS)
        .onChange(of: photoSelection) { _, items in
            handlePhotoSelection(items)
        }
        #endif
    }

    private var header: some View {
        HStack {
            SectionHeading("Attachments (\(model.details.attachments.count))")
            Spacer()
            #if !os(macOS)
            PhotosPicker(selection: $photoSelection, matching: .images) {
                Label("Photo", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            #endif
            Button {
                showingFileImporter = true
            } label: {
                Label("Upload", systemImage: "paperclip")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.details.attachments.isEmpty && model.inFlightUploads.isEmpty {
            Text("No attachments. Drop files here or use Upload.")
                .font(theme.typography.callout)
                .foregroundStyle(theme.palette.mutedForeground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, theme.spacing.l)
        } else {
            VStack(spacing: theme.spacing.s) {
                ForEach(model.inFlightUploads) { upload in
                    InFlightRow(upload: upload)
                }
                ForEach(model.details.attachments) { att in
                    AttachmentRow(
                        attachment: att,
                        onOpen: { open(att) },
                        onDelete: { pendingDelete = att },
                        isPreparingPreview: isPreparingPreview
                    )
                }
            }
        }
    }

    private func open(_ att: JiraAttachmentMeta) {
        if att.isImage {
            viewingImage = att
        } else {
            Task { await preview(att) }
        }
    }

    private func preview(_ att: JiraAttachmentMeta) async {
        guard let url = att.content else {
            env.toaster.error("No download URL on \(att.filename).")
            return
        }
        isPreparingPreview = true
        defer { isPreparingPreview = false }
        do {
            let local = try await env.api.downloadAttachment(url: url, suggestedFilename: att.filename)
            previewURL = local
        } catch {
            env.toaster.error("Couldn't open \(att.filename): \(error.localizedDescription)")
        }
    }

    #if !os(macOS)
    private func handlePhotoSelection(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        let snapshot = items
        photoSelection = []
        Task {
            for (index, item) in snapshot.enumerated() {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    let name = "Photo-\(Int(Date().timeIntervalSince1970))-\(index).jpg"
                    await model.uploadAttachment(
                        data: data,
                        filename: name,
                        mimeType: "image/jpeg"
                    )
                }
            }
        }
    }
    #endif
}

private struct InFlightRow: View {
    @Environment(\.balmTheme) private var theme
    let upload: IssueDetailViewModel.InFlightUpload

    var body: some View {
        HStack(spacing: theme.spacing.m) {
            ProgressView()
                .controlSize(.small)
                .frame(width: 36, height: 36)
                .background(theme.palette.secondary)
                .clipShape(RoundedRectangle(cornerRadius: theme.radii.sm))
            VStack(alignment: .leading, spacing: 2) {
                Text(upload.filename)
                    .font(theme.typography.body)
                    .foregroundStyle(theme.palette.foreground)
                    .lineLimit(1)
                Text("Uploading · \(ByteCountFormatter.string(fromByteCount: Int64(upload.size), countStyle: .file))")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.palette.mutedForeground)
            }
            Spacer()
        }
        .padding(.vertical, theme.spacing.xs)
    }
}

private struct AttachmentRow: View {
    @Environment(\.balmTheme) private var theme
    let attachment: JiraAttachmentMeta
    let onOpen: () -> Void
    let onDelete: () -> Void
    let isPreparingPreview: Bool

    var body: some View {
        HStack(spacing: theme.spacing.m) {
            iconOrThumbnail
                .frame(width: 36, height: 36)
                .background(theme.palette.secondary)
                .clipShape(RoundedRectangle(cornerRadius: theme.radii.sm))

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.filename)
                    .font(theme.typography.body)
                    .foregroundStyle(theme.palette.foreground)
                    .lineLimit(1)
                Text("\(prettySize(attachment.size))\(attachment.mimeType.map { " · \($0)" } ?? "")")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.palette.mutedForeground)
            }
            Spacer()
            if isPreparingPreview {
                ProgressView().controlSize(.small)
            }
            Menu {
                Button(attachment.isImage ? "View" : "Preview", systemImage: "eye", action: onOpen)
                Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(theme.palette.mutedForeground)
                    .padding(.horizontal, theme.spacing.xs)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.vertical, theme.spacing.xs)
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
    }

    @ViewBuilder
    private var iconOrThumbnail: some View {
        if attachment.isImage, let url = attachment.thumbnail ?? attachment.content {
            JiraImageView(url: url, contentMode: .fill) { _ in
                Image(systemName: "photo")
                    .foregroundStyle(theme.palette.mutedForeground)
            }
        } else {
            Image(systemName: systemImage(for: attachment.mimeType))
                .foregroundStyle(theme.palette.mutedForeground)
        }
    }

    private func systemImage(for mime: String?) -> String {
        guard let mime else { return "doc" }
        if mime.hasPrefix("video/") { return "play.rectangle" }
        if mime.hasPrefix("audio/") { return "waveform" }
        if mime == "application/pdf" { return "doc.richtext" }
        if mime.hasPrefix("text/") { return "doc.text" }
        if mime.contains("zip") || mime.contains("compressed") { return "archivebox" }
        return "doc"
    }

    private func prettySize(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
