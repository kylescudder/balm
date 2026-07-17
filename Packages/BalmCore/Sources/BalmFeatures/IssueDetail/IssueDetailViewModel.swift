import Foundation
import ImageIO
import Observation
import BalmModels
import BalmAPI

@MainActor
@Observable
public final class IssueDetailViewModel {
    public enum LoadState: Sendable, Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    public let issueKey: String
    public private(set) var issue: JiraIssue? {
        didSet {
            // Mirror every change (load + optimistic mutations + rollbacks) to
            // the board/list so the card reflects edits without a manual reload.
            if let issue {
                NotificationCenter.default.post(
                    name: .balmIssueUpdated, object: nil, userInfo: ["issue": issue]
                )
            }
        }
    }
    public private(set) var details: JiraIssueDetails = .init()
    public private(set) var transitions: [JiraTransition] = []
    public private(set) var loadState: LoadState = .idle

    private let api: JiraClient
    let toaster: Toaster?
    private var loadTask: Task<Void, Never>?

    public var currentUser: JiraUser?

    public init(
        issueKey: String,
        api: JiraClient,
        seedIssue: JiraIssue? = nil,
        toaster: Toaster? = nil,
        currentUser: JiraUser? = nil
    ) {
        self.issueKey = issueKey
        self.api = api
        self.issue = seedIssue
        self.toaster = toaster
        self.currentUser = currentUser
    }

    public func loadIfNeeded() {
        guard issue == nil || loadState == .idle else { return }
        reload()
    }

    public func reload() {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            await self?.performLoad()
        }
    }

    private func performLoad() async {
        loadState = .loading
        do {
            async let detailReq = api.send(IssueEndpoints.GetDetail(issueKey: issueKey))
            async let transitionsReq = api.send(IssueEndpoints.Transitions(issueKey: issueKey))

            let instanceField = await api.resolveInstanceFieldID()
            let raw = try await detailReq
            let (mapped, bundle) = IssueDetailMapper.decode(raw, instanceFieldID: instanceField)
            issue = mapped
            details = bundle

            // Transitions can fail independently (permissions etc) — don't blow up the screen.
            if let response = try? await transitionsReq {
                transitions = response.transitions
            }
            loadState = .loaded
        } catch is CancellationError {
            return
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Mutations

    /// Apply a workflow transition. Optimistically sets the target status; on
    /// failure, rolls back and refetches transitions.
    public func applyTransition(_ transition: JiraTransition) async {
        guard var current = issue else { return }
        let snapshot = current
        current.status = transition.to
        issue = current
        do {
            try await api.sendVoid(IssueEndpoints.ApplyTransition(
                issueKey: issueKey,
                transitionID: transition.id
            ))
            toaster?.success("Moved to \(StatusNormaliser.normalise(transition.to.name))")
            // Transitions depend on the new state — refresh.
            if let resp = try? await api.send(IssueEndpoints.Transitions(issueKey: issueKey)) {
                transitions = resp.transitions
            }
        } catch {
            issue = snapshot
            toaster?.error("Couldn't change status: \(error.localizedDescription)")
        }
    }

    public func setAssignee(_ user: JiraUser?) async {
        guard var current = issue else { return }
        let snapshot = current
        current.assignee = user.map { JiraUserSummary(displayName: $0.displayName, avatarUrls: $0.avatarUrls) }
        issue = current
        do {
            try await api.sendVoid(IssueEndpoints.Assign(issueKey: issueKey, accountID: user?.accountId))
            toaster?.success(user.map { "Assigned to \($0.displayName)" } ?? "Unassigned")
        } catch {
            issue = snapshot
            toaster?.error("Couldn't reassign: \(error.localizedDescription)")
        }
    }

    public func setPriority(_ name: String) async {
        await updateField(
            patch: IssueFieldPatch.priority(name: name),
            optimistic: { $0.priority = JiraPriority(name: name) },
            success: "Priority set to \(name)"
        )
    }

    public func setDueDate(_ value: String?) async {
        await updateField(
            patch: IssueFieldPatch.dueDate(value),
            optimistic: { $0.dueDate = value },
            success: value.map { "Due \($0)" } ?? "Due date cleared"
        )
    }

    public func setLabels(_ labels: [String]) async {
        await updateField(
            patch: IssueFieldPatch.labels(labels),
            optimistic: { $0.labels = labels },
            success: "Labels updated"
        )
    }

    public func setComponents(names: [String]) async {
        await updateField(
            patch: IssueFieldPatch.components(names: names),
            optimistic: { $0.components = names.map { JiraComponent(name: $0) } },
            success: "Components updated"
        )
    }

    public func setFixVersions(_ versions: [JiraVersion]) async {
        await updateField(
            patch: IssueFieldPatch.fixVersions(ids: versions.map(\.id)),
            optimistic: { $0.fixVersions = versions },
            success: "Fix versions updated"
        )
    }

    public func setDescription(plainText text: String) async {
        await updateField(
            patch: IssueFieldPatch.description(plainText: text),
            optimistic: { $0.descriptionText = text },
            success: "Description updated"
        )
    }

    /// Sprint mutation uses the agile API (move issue between sprint/backlog),
    /// not the customfield. `nil` moves to backlog.
    public func setSprint(_ sprint: JiraSprint?) async {
        guard var current = issue else { return }
        let snapshot = current
        current.sprint = sprint
        issue = current
        do {
            if let sprint, let id = Int(sprint.id) {
                try await api.sendVoid(IssueEndpoints.AddToSprint(sprintID: id, issueKeys: [issueKey]))
                toaster?.success("Moved to \(sprint.name)")
            } else {
                try await api.sendVoid(IssueEndpoints.MoveToBacklog(issueKeys: [issueKey]))
                toaster?.success("Moved to backlog")
            }
        } catch {
            issue = snapshot
            toaster?.error("Couldn't change sprint: \(error.localizedDescription)")
        }
    }

    // MARK: - Issue links

    /// Add a typed link to another issue. `direction` is from this issue's
    /// perspective — `.outward` means *this* issue does the outward verb
    /// (e.g. "blocks" target). On success the issue detail is refreshed so
    /// the link's real id and full target metadata land in `details`.
    public func addLink(
        type: JiraIssueLink.LinkType,
        direction: JiraIssueLink.Direction,
        target: JiraIssueLink.LinkedIssue
    ) async {
        let tempID = "tmp-link-\(UUID().uuidString)"
        let optimistic = JiraIssueLink(
            id: tempID,
            type: type,
            direction: direction,
            relationship: direction == .outward ? type.outward : type.inward,
            issue: target
        )
        details.issueLinks.append(optimistic)

        let inward = direction == .inward ? issueKey : target.key
        let outward = direction == .outward ? issueKey : target.key

        do {
            try await api.sendVoid(IssueEndpoints.AddLink(
                typeName: type.name,
                inwardIssueKey: inward,
                outwardIssueKey: outward
            ))
            // Refresh to replace the placeholder with the real link.
            await refreshAfterLinkChange(removingTempID: tempID)
            toaster?.success("Linked to \(target.key)")
        } catch {
            details.issueLinks.removeAll { $0.id == tempID }
            toaster?.error("Couldn't link: \(error.localizedDescription)")
        }
    }

    public func removeLink(id: String) async {
        guard let index = details.issueLinks.firstIndex(where: { $0.id == id }) else { return }
        let snapshot = details.issueLinks[index]
        details.issueLinks.remove(at: index)
        do {
            try await api.sendVoid(IssueEndpoints.RemoveLink(linkID: id))
            toaster?.success("Link removed")
        } catch {
            details.issueLinks.insert(snapshot, at: min(index, details.issueLinks.count))
            toaster?.error("Couldn't remove link: \(error.localizedDescription)")
        }
    }

    private func refreshAfterLinkChange(removingTempID tempID: String) async {
        do {
            let raw = try await api.send(IssueEndpoints.GetDetail(issueKey: issueKey))
            let (_, bundle) = IssueDetailMapper.decode(raw)
            details.issueLinks = bundle.issueLinks
        } catch {
            // Best-effort — keep the placeholder removed regardless.
            details.issueLinks.removeAll { $0.id == tempID }
        }
    }

    // MARK: - Comments

    /// Post a new comment optimistically. A temporary local entry appears
    /// immediately and is replaced (or removed) once the server responds.
    public func addComment(plainText: String) async {
        let trimmed = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let tempID = "tmp-\(UUID().uuidString)"
        let optimistic = JiraComment(
            id: tempID,
            author: JiraUserSummary(
                displayName: currentUser?.displayName ?? "You",
                avatarUrls: currentUser?.avatarUrls
            ),
            created: Date(),
            updated: nil,
            body: trimmed,
            bodyADF: nil
        )
        details.comments.append(optimistic)

        do {
            let raw = try await api.send(IssueEndpoints.AddComment(
                issueKey: issueKey,
                plainText: trimmed
            ))
            let mapped = IssueDetailMapper.comment(from: raw)
            if let index = details.comments.firstIndex(where: { $0.id == tempID }) {
                details.comments[index] = mapped
            } else {
                details.comments.append(mapped)
            }
            toaster?.success("Comment added")
        } catch {
            details.comments.removeAll { $0.id == tempID }
            toaster?.error("Couldn't post comment: \(error.localizedDescription)")
        }
    }

    /// An image queued for a comment (pasted into the composer).
    public struct PastedImage: Identifiable, Sendable {
        public let id = UUID()
        public let data: Data
        public let filename: String
        public let mimeType: String?
    }

    /// Search assignable users for @mention autocomplete in the composer.
    /// Returns [] on failure so the dropdown just shows nothing.
    public func searchMentionUsers(query: String) async -> [JiraUser] {
        let projectKey = String(issueKey.split(separator: "-").first ?? "")
        guard !projectKey.isEmpty else { return [] }
        return (try? await api.send(
            UserEndpoints.MentionSearch(projectKey: projectKey, query: query)
        )) ?? []
    }

    /// Plain-text comment with images (no mentions). Thin wrapper over the
    /// rich-content path.
    public func addComment(plainText: String, images: [PastedImage]) async {
        await addComment(content: [.text(plainText)], images: images)
    }

    /// Post a comment built from rich fragments (text + @mentions) plus inline
    /// images. Each image is uploaded as an attachment, its Media-services UUID
    /// resolved, then embedded as an ADF `media` node so it renders inline.
    /// Mentions become ADF `mention` nodes that notify the person in Jira.
    public func addComment(content: [CommentInline], images: [PastedImage]) async {
        let plain = content.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isBlank || !images.isEmpty else { return }

        let tempID = "tmp-\(UUID().uuidString)"
        let optimistic = JiraComment(
            id: tempID,
            author: JiraUserSummary(
                displayName: currentUser?.displayName ?? "You",
                avatarUrls: currentUser?.avatarUrls
            ),
            created: Date(),
            updated: nil,
            body: images.isEmpty ? plain : (plain.isEmpty ? "🖼 \(images.count) image(s)" : plain),
            bodyADF: nil
        )
        details.comments.append(optimistic)

        do {
            // Upload each image, resolve its media UUID for the ADF node.
            var mediaFileIDs: [String] = []
            for image in images {
                let raws = try await api.send(IssueEndpoints.UploadAttachment(
                    issueKey: issueKey,
                    data: image.data,
                    filename: image.filename,
                    mimeType: image.mimeType ?? "image/png"
                ))
                details.attachments.append(contentsOf: raws.map(Self.mapAttachment))
                for raw in raws {
                    if let url = raw.content, let id = await api.mediaFileID(forContentURL: url) {
                        mediaFileIDs.append(id)
                    }
                }
            }

            let raw = try await api.send(IssueEndpoints.AddComment(
                issueKey: issueKey,
                content: content,
                mediaFileIDs: mediaFileIDs
            ))
            let mapped = IssueDetailMapper.comment(from: raw)
            if let index = details.comments.firstIndex(where: { $0.id == tempID }) {
                details.comments[index] = mapped
            } else {
                details.comments.append(mapped)
            }
            toaster?.success(images.isEmpty ? "Comment added" : "Comment added with \(images.count) image(s)")
        } catch {
            details.comments.removeAll { $0.id == tempID }
            toaster?.error("Couldn't post comment: \(error.localizedDescription)")
        }
    }

    /// Post a comment from ordered composer fragments (text, @mentions, and
    /// inline images). Images are uploaded as attachments and swapped for their
    /// resolved Media id in place, so they land exactly where they sat in the
    /// editor. Mentions become ADF `mention` nodes that notify the person.
    func addComment(draft segments: [DraftSegment]) async {
        let plain = draftPlainText(segments).trimmingCharacters(in: .whitespacesAndNewlines)
        let hasImage = segments.contains { if case .image = $0 { return true } else { return false } }
        guard !plain.isEmpty || hasImage else { return }

        let tempID = "tmp-\(UUID().uuidString)"
        let optimistic = JiraComment(
            id: tempID,
            author: JiraUserSummary(
                displayName: currentUser?.displayName ?? "You",
                avatarUrls: currentUser?.avatarUrls
            ),
            created: Date(),
            updated: nil,
            body: plain.isEmpty ? "🖼 image" : plain,
            bodyADF: nil
        )
        details.comments.append(optimistic)

        do {
            var resolved: [CommentSegment] = []
            for segment in segments {
                switch segment {
                case .text(let text):
                    resolved.append(.text(text))
                case .mention(let accountId, let display):
                    resolved.append(.mention(accountId: accountId, display: display))
                case .image(let image):
                    let raws = try await api.send(IssueEndpoints.UploadAttachment(
                        issueKey: issueKey,
                        data: image.data,
                        filename: image.filename,
                        mimeType: image.mimeType ?? "image/png"
                    ))
                    details.attachments.append(contentsOf: raws.map(Self.mapAttachment))
                    let pixelSize = Self.imagePixelSize(of: image.data)
                    for raw in raws {
                        if let url = raw.content, let id = await api.mediaFileID(forContentURL: url) {
                            resolved.append(.image(
                                mediaFileID: id,
                                width: pixelSize?.width,
                                height: pixelSize?.height
                            ))
                        }
                    }
                }
            }

            let raw = try await api.send(IssueEndpoints.AddComment(issueKey: issueKey, segments: resolved))
            let mapped = IssueDetailMapper.comment(from: raw)
            if let index = details.comments.firstIndex(where: { $0.id == tempID }) {
                details.comments[index] = mapped
            } else {
                details.comments.append(mapped)
            }
            toaster?.success(hasImage ? "Comment added with image" : "Comment added")
        } catch {
            details.comments.removeAll { $0.id == tempID }
            toaster?.error("Couldn't post comment: \(error.localizedDescription)")
        }
    }

    private func draftPlainText(_ segments: [DraftSegment]) -> String {
        segments.map {
            switch $0 {
            case .text(let text): return text
            case .mention(_, let display): return "@\(display)"
            case .image: return ""
            }
        }
        .joined()
    }

    public func editComment(id: String, plainText: String) async {
        let trimmed = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let index = details.comments.firstIndex(where: { $0.id == id }) else { return }

        let snapshot = details.comments[index]
        var updated = snapshot
        updated.body = trimmed
        updated.bodyADF = nil
        updated.updated = Date()
        details.comments[index] = updated

        do {
            let raw = try await api.send(IssueEndpoints.EditComment(
                issueKey: issueKey,
                commentID: id,
                plainText: trimmed
            ))
            if let index = details.comments.firstIndex(where: { $0.id == id }) {
                details.comments[index] = IssueDetailMapper.comment(from: raw)
            }
            toaster?.success("Comment updated")
        } catch {
            details.comments[index] = snapshot
            toaster?.error("Couldn't edit comment: \(error.localizedDescription)")
        }
    }

    public func deleteComment(id: String) async {
        guard let index = details.comments.firstIndex(where: { $0.id == id }) else { return }
        let snapshot = details.comments[index]
        details.comments.remove(at: index)

        do {
            try await api.sendVoid(IssueEndpoints.DeleteComment(
                issueKey: issueKey,
                commentID: id
            ))
            toaster?.success("Comment deleted")
        } catch {
            details.comments.insert(snapshot, at: min(index, details.comments.count))
            toaster?.error("Couldn't delete comment: \(error.localizedDescription)")
        }
    }

    // MARK: - Attachments

    public private(set) var inFlightUploads: [InFlightUpload] = []

    public struct InFlightUpload: Identifiable, Sendable, Equatable {
        public let id: UUID
        public let filename: String
        public let size: Int
    }

    /// Upload raw bytes optimistically. A placeholder row appears in
    /// `inFlightUploads` for the duration of the request.
    public func uploadAttachment(data: Data, filename: String, mimeType: String?) async {
        let upload = InFlightUpload(id: UUID(), filename: filename, size: data.count)
        inFlightUploads.append(upload)
        defer { inFlightUploads.removeAll { $0.id == upload.id } }

        do {
            let raws = try await api.send(IssueEndpoints.UploadAttachment(
                issueKey: issueKey,
                data: data,
                filename: filename,
                mimeType: mimeType ?? "application/octet-stream"
            ))
            let mapped = raws.map(Self.mapAttachment)
            details.attachments.append(contentsOf: mapped)
            toaster?.success(raws.count == 1 ? "Uploaded \(filename)" : "Uploaded \(raws.count) files")
        } catch {
            toaster?.error("Upload failed: \(error.localizedDescription)")
        }
    }

    /// Upload a file by URL — reads the bytes off the main actor and dispatches
    /// to `uploadAttachment(data:filename:mimeType:)`.
    public func uploadAttachment(fileURL: URL) async {
        let filename = fileURL.lastPathComponent
        let mimeType = Self.mimeType(forExtension: fileURL.pathExtension)
        let isAccessSecurityScoped = fileURL.startAccessingSecurityScopedResource()
        defer { if isAccessSecurityScoped { fileURL.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: fileURL)
            await uploadAttachment(data: data, filename: filename, mimeType: mimeType)
        } catch {
            toaster?.error("Couldn't read \(filename): \(error.localizedDescription)")
        }
    }

    public func deleteAttachment(id: String) async {
        guard let index = details.attachments.firstIndex(where: { $0.id == id }) else { return }
        let snapshot = details.attachments[index]
        details.attachments.remove(at: index)
        do {
            try await api.sendVoid(IssueEndpoints.DeleteAttachment(attachmentID: id))
            toaster?.success("Deleted \(snapshot.filename)")
        } catch {
            details.attachments.insert(snapshot, at: min(index, details.attachments.count))
            toaster?.error("Couldn't delete: \(error.localizedDescription)")
        }
    }

    /// Pixel dimensions read from the image header (no bitmap decode). EXIF
    /// orientations 5–8 render rotated 90°, so width/height swap.
    nonisolated private static func imagePixelSize(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        if let orientation = props[kCGImagePropertyOrientation] as? UInt32, orientation >= 5 {
            return (height, width)
        }
        return (width, height)
    }

    nonisolated private static func mapAttachment(_ raw: RawJiraAttachment) -> JiraAttachmentMeta {
        JiraAttachmentMeta(
            id: raw.id,
            filename: raw.filename,
            size: raw.size,
            mimeType: raw.mimeType,
            isImage: raw.mimeType?.hasPrefix("image/") ?? false,
            content: raw.content,
            thumbnail: raw.thumbnail,
            created: raw.created
        )
    }

    private static func mimeType(forExtension ext: String) -> String {
        let lower = ext.lowercased()
        switch lower {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        case "pdf": return "application/pdf"
        case "txt", "md", "log": return "text/plain"
        case "json": return "application/json"
        case "csv": return "text/csv"
        case "zip": return "application/zip"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        default: return "application/octet-stream"
        }
    }

    // MARK: - Helpers

    private func updateField(
        patch: (String, AnyJSON),
        optimistic: (inout JiraIssue) -> Void,
        success message: String
    ) async {
        guard var current = issue else { return }
        let snapshot = current
        optimistic(&current)
        issue = current
        do {
            try await api.sendVoid(IssueEndpoints.UpdateFields(
                issueKey: issueKey,
                fields: [patch.0: patch.1]
            ))
            toaster?.success(message)
        } catch {
            issue = snapshot
            toaster?.error("Update failed: \(error.localizedDescription)")
        }
    }
}
