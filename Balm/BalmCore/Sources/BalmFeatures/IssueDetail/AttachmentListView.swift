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
        #if os(iOS)
        iosSections
        #else
        macBody
        #endif
    }

    #if os(iOS)
    @ViewBuilder
    private var iosSections: some View {
        Section("Attachments") {
            PhotosPicker(selection: $photoSelection, matching: .images) {
                Label("Add photo", systemImage: "photo.on.rectangle")
            }
            Button {
                showingFileImporter = true
            } label: {
                Label("Upload file", systemImage: "paperclip")
            }

            if model.details.attachments.isEmpty && model.inFlightUploads.isEmpty {
                Text("No attachments")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.inFlightUploads) { upload in
                    HStack {
                        ProgressView()
                        VStack(alignment: .leading) {
                            Text(upload.filename)
                            Text("Uploading, \(ByteCountFormatter.string(fromByteCount: Int64(upload.size), countStyle: .file))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                ForEach(model.details.attachments) { attachment in
                    Button {
                        open(attachment)
                    } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text(attachment.filename)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text("\(prettySize(attachment.size))\(attachment.mimeType.map { ", \($0)" } ?? "")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: attachment.isImage ? "photo" : systemImage(for: attachment.mimeType))
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            pendingDelete = attachment
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button(attachment.isImage ? "View" : "Preview", systemImage: "eye") { open(attachment) }
                        Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = attachment }
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true,
            onCompletion: handleFileImport
        )
        .confirmationDialog(
            "Delete this attachment?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { attachment in
            Button("Delete", role: .destructive) {
                Task { await model.deleteAttachment(id: attachment.id) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { attachment in
            Text(attachment.filename)
        }
        .quickLookPreview($previewURL)
        .sheet(item: $viewingImage) { attachment in
            ImageViewerSheet(attachment: attachment)
        }
        .onChange(of: photoSelection) { _, items in
            handlePhotoSelection(items)
        }
    }
    #endif

    private var macBody: some View {
        VStack(alignment: .leading, spacing: theme.spacing.m) {
            header
            content
        }
        .padding(theme.spacing.s)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.clear,
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
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
                env.toaster.report(error, "Couldn't open file")
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
        SectionHeading("Attachments", count: model.details.attachments.count) {
            HStack(spacing: 8) {
                #if !os(macOS)
                PhotosPicker(selection: $photoSelection, matching: .images) {
                    Label("Photo", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.borderless)
                #endif
                Button {
                    showingFileImporter = true
                } label: {
                    Label("Upload", systemImage: "paperclip")
                }
                .buttonStyle(.borderless)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.details.attachments.isEmpty && model.inFlightUploads.isEmpty {
            Text("No attachments. Drop files here or use Upload.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, theme.spacing.s)
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

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                Task { await model.uploadAttachment(fileURL: url) }
            }
        case .failure(let error):
            env.toaster.report(error, "Couldn't open file")
        }
    }

    private func prettySize(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
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
            env.toaster.report(error, "Couldn't open \(att.filename)")
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
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(upload.filename)
                    .lineLimit(1)
                Text("Uploading, \(ByteCountFormatter.string(fromByteCount: Int64(upload.size), countStyle: .file))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.filename)
                    .lineLimit(1)
                Text("\(prettySize(attachment.size))\(attachment.mimeType.map { ", \($0)" } ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
            }
        } else {
            Image(systemName: systemImage(for: attachment.mimeType))
                .foregroundStyle(.secondary)
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
