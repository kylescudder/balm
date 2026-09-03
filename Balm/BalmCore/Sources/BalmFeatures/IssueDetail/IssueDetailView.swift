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

/// One issue, one column, the same order everywhere: key and actions, title,
/// quick properties, the property grid, description, attachments, links,
/// comments, activity. On the Mac this is the inspector; on iOS and iPad it is
/// the detail column.
public struct IssueDetailView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.balmTheme) private var theme
    @Environment(\.openURL) private var openURL

    @State private var model: IssueDetailViewModel
    @State private var editingDescription = false
    /// Which field picker is open. Shared by the quick-property buttons, the
    /// grid rows and the single-key shortcuts, so they all open the same sheet.
    @State private var editingField: EditableField?
    /// Bumped by the C shortcut; the comment composer takes focus.
    @State private var commentFocusRequest = 0
    @State private var copiedKey = false
    @State private var copiedURL = false
    @State private var isHoveringKey = false
    private let initialIssue: JiraIssue
    private let note: IssueVisibilityNote?
    private let onClose: (() -> Void)?
    private let renderer = ADFRenderer()

    init(issue: JiraIssue, note: IssueVisibilityNote?, onClose: (() -> Void)? = nil) {
        self.initialIssue = issue
        self.note = note
        self.onClose = onClose
        let placeholderAPI = BalmAPI_PlaceholderForState.shared.api
        self._model = State(initialValue: IssueDetailViewModel(
            issueKey: issue.key,
            api: placeholderAPI,
            seedIssue: issue
        ))
    }

    public init(issue: JiraIssue, onClose: (() -> Void)? = nil) {
        self.initialIssue = issue
        self.note = nil
        self.onClose = onClose
        let placeholderAPI = BalmAPI_PlaceholderForState.shared.api
        self._model = State(initialValue: IssueDetailViewModel(
            issueKey: issue.key,
            api: placeholderAPI,
            seedIssue: issue
        ))
    }

    public var body: some View {
        Group {
            #if os(iOS)
            iosBody
            #else
            macBody
            #endif
        }
        .task(id: initialIssue.key) { await reconnectAndLoad() }
        .background { issueShortcutSink }
        .sheet(isPresented: $editingDescription) {
            DescriptionEditorView(
                initial: descriptionPlainText,
                onApply: { value in
                    Task { await model.setDescription(plainText: value) }
                }
            )
        }
    }

    // MARK: - macOS inspector

    private var macBody: some View {
        ScrollViewReader { proxy in
            macScroll
                .onChange(of: commentFocusRequest) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(Self.commentsAnchor, anchor: .bottom)
                    }
                }
        }
    }

    private static let commentsAnchor = "comments"

    private var macScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                Text(currentIssue.summary)
                    .font(theme.typography.issueTitle)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if let note {
                    VisibilityNoteView(note: note)
                }
                if case .failed(let message) = model.loadState {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                IssueMetadataPanel(model: model, editingField: $editingField)
                Divider()
                descriptionSection
                AttachmentListView(model: model)
                IssueLinkListView(model: model)
                CommentListView(model: model, focusRequest: commentFocusRequest)
                    .id(Self.commentsAnchor)
                ChangelogView(entries: model.details.changelog)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Declared inside the inspector, so these land in the inspector's own
        // toolbar zone on macOS 26 rather than crowding the content's.
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                if let url = issueBrowseURL {
                    Button {
                        openURL(url)
                    } label: {
                        Label("Open in Jira", systemImage: "arrow.up.right.square")
                    }
                    .help("Open \(currentIssue.key) in Jira")
                }
                Button {
                    model.reload()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh")
                if let onClose {
                    Button(action: onClose) {
                        Label("Close", systemImage: "xmark")
                    }
                    .keyboardShortcut(.escape, modifiers: [])
                    .help("Close (Esc)")
                }
            }
        }
    }

    /// The key, copyable, with a loading indicator while the latest detail
    /// arrives. Actions live in the inspector toolbar.
    private var header: some View {
        HStack(spacing: 8) {
            keyBadge
            if case .loading = model.loadState {
                ProgressView().controlSize(.small)
            }
            Spacer()
        }
        .foregroundStyle(.secondary)
    }

    // MARK: - iOS detail

    #if os(iOS)
    private var iosBody: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    Text(currentIssue.summary)
                        .font(theme.typography.issueTitle)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    if case .loading = model.loadState {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Loading the latest")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if case .failed(let message) = model.loadState {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    if let note {
                        VisibilityNoteView(note: note)
                    }
                    IssueQuickProperties(model: model, editingField: $editingField)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 8, trailing: 4))
            }

            IssueMetadataPanel(model: model, editingField: $editingField)

            Section("Description") {
                descriptionContent
                Button("Edit description") { editingDescription = true }
            }

            AttachmentListView(model: model)
            IssueLinkListView(model: model)
            Section {
                CommentListView(model: model, focusRequest: commentFocusRequest)
            }
            Section {
                ChangelogView(entries: model.details.changelog)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(currentIssue.key)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let url = issueBrowseURL {
                    Button {
                        openURL(url)
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .accessibilityLabel("Open in Jira")
                }
                Menu {
                    Button("Refresh", systemImage: "arrow.clockwise") { model.reload() }
                    Button("Copy key", systemImage: "doc.on.doc") { copyKey() }
                    if issueBrowseURL != nil {
                        Button("Copy link", systemImage: "link") { copyURL() }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More")
            }
        }
    }
    #endif

    // MARK: - Keyboard

    /// Single keys act on the open issue. They are invisible buttons so they
    /// never fire while a text field has focus, and they open exactly the
    /// sheet the matching button opens.
    private var issueShortcutSink: some View {
        Group {
            Button("Status") { editingField = .status }
                .keyboardShortcut("s", modifiers: [])
            Button("Assignee") { editingField = .assignee }
                .keyboardShortcut("a", modifiers: [])
            Button("Priority") { editingField = .priority }
                .keyboardShortcut("p", modifiers: [])
            Button("Labels") { editingField = .labels }
                .keyboardShortcut("l", modifiers: [])
            Button("Due date") { editingField = .dueDate }
                .keyboardShortcut("d", modifiers: [])
            Button("Components") { editingField = .components }
                .keyboardShortcut("m", modifiers: [])
            Button("Fix version") { editingField = .versions }
                .keyboardShortcut("v", modifiers: [])
            Button("Edit description") { editingDescription = true }
                .keyboardShortcut("e", modifiers: [])
            Button("Comment") { commentFocusRequest += 1 }
                .keyboardShortcut("c", modifiers: [])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    // MARK: - Description

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading("Description") {
                Button("Edit") { editingDescription = true }
                    .buttonStyle(.borderless)
                    .help("Edit description (E)")
            }
            descriptionContent
        }
    }

    @ViewBuilder
    private var descriptionContent: some View {
        if let adf = currentIssue.descriptionADF,
           let blocks = try? renderer.render(json: adf, attachments: model.details.attachments) {
            ADFContentView(blocks: blocks)
        } else if let text = currentIssue.descriptionText, !text.isEmpty {
            Text(text)
                .textSelection(.enabled)
        } else {
            Text(isLoaded ? "No description." : "Loading description")
                .foregroundStyle(.secondary)
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

    // MARK: - Key badge

    /// The issue key (click to copy) plus a hover-revealed copy-link button.
    /// Feedback is a brief inline tick, not a toast.
    private var keyBadge: some View {
        HStack(spacing: 4) {
            Button { copyKey() } label: {
                HStack(spacing: 3) {
                    Text(currentIssue.key)
                        .monospacedDigit()
                    if copiedKey {
                        Image(systemName: "checkmark")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.tint)
                    }
                }
            }
            .help("Copy \(currentIssue.key)")

            Button { copyURL() } label: {
                Image(systemName: copiedURL ? "checkmark" : "link")
                    .font(.caption2)
                    .foregroundStyle(copiedURL ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            }
            .help("Copy link to \(currentIssue.key)")
            .opacity(showLinkButton ? 1 : 0)
        }
        .buttonStyle(.plain)
        // The whole badge (including the transparent icon slot) is one hover
        // region, so the cursor can travel to the icon without it vanishing.
        .contentShape(Rectangle())
        .onHover { isHoveringKey = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHoveringKey)
        .animation(.easeInOut(duration: 0.12), value: copiedKey)
        .animation(.easeInOut(duration: 0.12), value: copiedURL)
    }

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

/// Why this issue was not in the view, and the one action that would show it.
struct VisibilityNoteView: View {
    let note: IssueVisibilityNote

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: note.systemImage)
                .foregroundStyle(.secondary)
            Text(note.text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let title = note.actionTitle, let action = note.action {
                Button(title, action: action)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .fixedSize()
            }
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
