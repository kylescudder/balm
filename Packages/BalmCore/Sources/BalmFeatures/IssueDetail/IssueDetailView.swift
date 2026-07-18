import SwiftUI
import BalmModels
import BalmAPI
import BalmADF
import BalmDesignSystem
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public struct IssueDetailView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.balmTheme) private var theme
    @Environment(\.openURL) private var openURL

    @State private var model: IssueDetailViewModel
    private let initialIssue: JiraIssue
    private let onClose: (() -> Void)?
    private let renderer = ADFRenderer()

    public init(issue: JiraIssue, onClose: (() -> Void)? = nil) {
        self.initialIssue = issue
        self.onClose = onClose
        let placeholderAPI = BalmAPI_PlaceholderForState.shared.api
        self._model = State(initialValue: IssueDetailViewModel(
            issueKey: issue.key,
            api: placeholderAPI,
            seedIssue: issue
        ))
    }

    public var body: some View {
        #if os(iOS)
        iosBody
            .task(id: initialIssue.key) { await reconnectAndLoad() }
            .id(initialIssue.key)
        #else
        macBody
            .task(id: initialIssue.key) { await reconnectAndLoad() }
            .id(initialIssue.key)
        #endif
    }

    #if os(iOS)
    private var iosBody: some View {
        NavigationStack {
            Form {
                Section {
                    Text(currentIssue.summary)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if case .loading = model.loadState {
                        HStack {
                            ProgressView()
                            Text("Loading latest issue details…")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if case .failed(let message) = model.loadState {
                        Text(message)
                            .foregroundStyle(.red)
                    }
                }

                descriptionSection
                IssueMetadataPanel(model: model)
                AttachmentListView(model: model)
                IssueLinkListView(model: model)
                CommentListView(model: model)
                ChangelogView(entries: model.details.changelog)
            }
            .navigationTitle(currentIssue.key)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let onClose {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", action: onClose)
                    }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if let url = issueBrowseURL {
                        Button {
                            openURL(url)
                        } label: {
                            Image(systemName: "safari")
                        }
                        .accessibilityLabel("Open in Jira")
                    }
                    Button {
                        model.reload()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh")
                }
            }
        }
    }
    #endif

    private var macBody: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing.xl) {
                    header
                    // Two columns only when there's genuine room; otherwise a
                    // single column so the narrow inspector stays readable.
                    if geo.size.width >= 900 {
                        horizontalLayout
                    } else {
                        verticalLayout
                    }
                }
                .padding(theme.spacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s) {
            HStack(spacing: theme.spacing.s) {
                keyBadge
                StatusChip(status: currentIssue.status.name)
                if case .loading = model.loadState {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                if let url = issueBrowseURL {
                    Button { openURL(url) } label: {
                        Text("🦕")
                    }
                    .buttonStyle(.borderless)
                    .help("Open \(currentIssue.key) in Jira")
                    .accessibilityLabel("Open \(currentIssue.key) in Jira")
                }
                Button { model.reload() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh")
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(theme.palette.mutedForeground)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: [])
                    .help("Close")
                }
            }
            Text(currentIssue.summary)
                .font(theme.typography.title)
                .foregroundStyle(theme.palette.foreground)
                .fixedSize(horizontal: false, vertical: true)

            if case .failed(let message) = model.loadState {
                Text(message)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.palette.destructive)
            }
        }
    }

    private var horizontalLayout: some View {
        HStack(alignment: .top, spacing: theme.spacing.xl) {
            mainColumn
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: theme.spacing.xl) {
                IssueMetadataPanel(model: model)
            }
            .frame(maxWidth: 340, alignment: .top)
        }
    }

    private var verticalLayout: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xl) {
            descriptionSection
            IssueMetadataPanel(model: model)
            AttachmentListView(model: model)
            IssueLinkListView(model: model)
            CommentListView(model: model)
            ChangelogView(entries: model.details.changelog)
        }
    }

    private var mainColumn: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xl) {
            descriptionSection
            AttachmentListView(model: model)
            IssueLinkListView(model: model)
            CommentListView(model: model)
            ChangelogView(entries: model.details.changelog)
        }
    }

    @State private var editingDescription = false

    private var descriptionSection: some View {
        Group {
            #if os(iOS)
            Section("Description") {
                descriptionContent
                Button {
                    editingDescription = true
                } label: {
                    Label("Edit Description", systemImage: "pencil")
                }
            }
            #else
            VStack(alignment: .leading, spacing: theme.spacing.m) {
                HStack {
                    SectionHeading("Description")
                    Spacer()
                    Button {
                        editingDescription = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
                descriptionContent
            }
            #endif
        }
        .sheet(isPresented: $editingDescription) {
            DescriptionEditorView(
                initial: descriptionPlainText,
                onApply: { value in
                    Task { await model.setDescription(plainText: value) }
                }
            )
        }
    }

    @ViewBuilder
    private var descriptionContent: some View {
        if let adf = currentIssue.descriptionADF,
           let blocks = try? renderer.render(json: adf, attachments: model.details.attachments) {
            ADFContentView(blocks: blocks)
        } else if let text = currentIssue.descriptionText, !text.isEmpty {
            Text(text)
                #if !os(iOS)
                .font(theme.typography.body)
                .foregroundStyle(theme.palette.foreground)
                #endif
        } else {
            Text(isLoaded ? "No description." : "Loading description…")
                .foregroundStyle(.secondary)
                #if !os(iOS)
                .font(theme.typography.callout)
                #endif
        }
    }

    private var descriptionPlainText: String {
        if let text = currentIssue.descriptionText, !text.isEmpty { return text }
        if let adf = currentIssue.descriptionADF,
           let blocks = try? renderer.render(json: adf) {
            return blocks.compactMap { block -> String? in
                if case .paragraph(let attr) = block { return String(attr.characters) }
                if case .heading(_, let attr) = block { return String(attr.characters) }
                return nil
            }.joined(separator: "\n\n")
        }
        return ""
    }

    @State private var copiedKey = false
    @State private var copiedURL = false
    @State private var isHoveringKey = false

    /// The issue key (tap to copy) plus a hover-revealed copy-link button.
    /// Feedback is a brief inline green tick, not a toast.
    private var keyBadge: some View {
        HStack(spacing: theme.spacing.xs) {
            Button { copyKey() } label: {
                HStack(spacing: 3) {
                    Text(currentIssue.key)
                        .font(theme.typography.caption.monospaced())
                        .foregroundStyle(theme.palette.mutedForeground)
                    if copiedKey {
                        Image(systemName: "checkmark")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.green)
                    }
                }
            }
            .buttonStyle(.plain)
            .help("Copy \(currentIssue.key)")

            Button { copyURL() } label: {
                Image(systemName: copiedURL ? "checkmark" : "link")
                    .font(.caption2)
                    .foregroundStyle(copiedURL ? AnyShapeStyle(.green) : AnyShapeStyle(theme.palette.mutedForeground))
            }
            .buttonStyle(.plain)
            .help("Copy link to \(currentIssue.key)")
            .opacity(showLinkButton ? 1 : 0)
        }
        // Make the whole badge (including the transparent icon slot) a solid
        // hover region — otherwise hover drops the instant the cursor crosses
        // off the opaque key text into the hidden icon's space, so you could
        // never travel to the icon to click it.
        .contentShape(Rectangle())
        .onHover { isHoveringKey = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHoveringKey)
        .animation(.easeInOut(duration: 0.12), value: copiedKey)
        .animation(.easeInOut(duration: 0.12), value: copiedURL)
    }

    /// On macOS reveal the link button only on hover; touch platforms have no
    /// hover, so keep it visible there.
    private var showLinkButton: Bool {
        #if os(macOS)
        return isHoveringKey || copiedURL
        #else
        return true
        #endif
    }

    private func copyKey() {
        setClipboard(currentIssue.key)
        copiedKey = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            copiedKey = false
        }
    }

    private func copyURL() {
        guard let url = issueBrowseURL else { return }
        setClipboard(url.absoluteString)
        copiedURL = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            copiedURL = false
        }
    }

    private var issueBrowseURL: URL? {
        guard case .signedIn(_, let siteURL, _) = env.authState else { return nil }
        return siteURL.appendingPathComponent("browse").appendingPathComponent(currentIssue.key)
    }

    private func setClipboard(_ string: String) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #elseif canImport(UIKit)
        UIPasteboard.general.string = string
        #endif
    }

    private var currentIssue: JiraIssue {
        model.issue ?? initialIssue
    }

    private var isLoaded: Bool {
        if case .loaded = model.loadState { return true }
        return false
    }

    private func reconnectAndLoad() async {
        let user: JiraUser? = {
            if case .signedIn(_, _, let user) = env.authState { return user }
            return nil
        }()
        let real = IssueDetailViewModel(
            issueKey: initialIssue.key,
            api: env.api,
            seedIssue: initialIssue,
            toaster: env.toaster,
            currentUser: user
        )
        model = real
        real.loadIfNeeded()
    }
}
