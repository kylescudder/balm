import SwiftUI
import BalmModels
#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension NSAttributedString.Key {
    /// Marks a run as an @mention; the value is the user's Jira `accountId`.
    static let balmMention = NSAttributedString.Key("balmMention")
    /// On an inline image attachment: the raw image bytes (`Data`).
    static let balmImageData = NSAttributedString.Key("balmImageData")
    /// On an inline image attachment: the upload filename (`String`).
    static let balmImageName = NSAttributedString.Key("balmImageName")
    /// On an inline image attachment: the MIME type (`String`).
    static let balmImageMime = NSAttributedString.Key("balmImageMime")
}

/// An ordered fragment read out of the composer before posting. Images still
/// hold their local bytes here; the view model uploads them and swaps in the
/// resolved Media id.
enum DraftSegment: Sendable {
    case text(String)
    case mention(accountId: String, display: String)
    case image(IssueDetailViewModel.PastedImage)
}

/// An active `@query` the composer is resolving, plus where the `@` sits in the
/// editor's coordinate space so the suggestion list can anchor to the caret.
struct MentionQuery: Equatable {
    var text: String
    var anchor: CGRect
}

/// Lets the SwiftUI parent imperatively insert a chosen user into the editor
/// (e.g. when a suggestion row is tapped) without routing state mutations
/// through `updateNSView`. The bridge wires `perform` to its coordinator.
@MainActor
final class MentionController: ObservableObject {
    fileprivate var perform: ((JiraUser) -> Void)?
    fileprivate var performImage: ((IssueDetailViewModel.PastedImage) -> Void)?
    func insert(_ user: JiraUser) { perform?(user) }
    /// Insert an inline image at the caret (used by paste / drop / the button).
    func insert(image: IssueDetailViewModel.PastedImage) { performImage?(image) }
}

/// The `@`-token under the caret: the range to replace on commit and the query.
private struct MentionScan {
    let tokenRange: NSRange
    let query: String
}

/// Scan backwards from the caret for an `@`-token at a word boundary. Returns
/// nil if the caret isn't inside one (whitespace breaks the token; `a@b` style
/// mid-word `@`s are ignored).
private func scanMention(in text: NSString, caret: Int) -> MentionScan? {
    guard caret > 0, caret <= text.length else { return nil }
    let boundary = CharacterSet.whitespacesAndNewlines
    var i = caret - 1
    while i >= 0 {
        let c = unichar(text.character(at: i))
        if c == unichar(0x40) { // '@'
            if i > 0 {
                let prev = unichar(text.character(at: i - 1))
                if let scalar = UnicodeScalar(prev), !boundary.contains(scalar) { return nil }
            }
            let start = i + 1
            let range = NSRange(location: i, length: caret - i)
            let query = text.substring(with: NSRange(location: start, length: caret - start))
            return MentionScan(tokenRange: range, query: query)
        }
        if let scalar = UnicodeScalar(c), boundary.contains(scalar) { return nil }
        i -= 1
    }
    return nil
}

/// Walk the editor's attributed string into ordered draft fragments: image
/// attachments, @mention runs, and plain text — in document order, ready to
/// upload + serialise to ADF.
func draftSegments(from attributed: NSAttributedString) -> [DraftSegment] {
    var out: [DraftSegment] = []
    let ns = attributed.string as NSString
    attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attrs, range, _ in
        if let data = attrs[.balmImageData] as? Data {
            out.append(.image(IssueDetailViewModel.PastedImage(
                data: data,
                filename: attrs[.balmImageName] as? String ?? "image.png",
                mimeType: attrs[.balmImageMime] as? String
            )))
        } else if let accountId = attrs[.balmMention] as? String {
            let sub = ns.substring(with: range)
            let display = sub.hasPrefix("@") ? String(sub.dropFirst()) : sub
            out.append(.mention(accountId: accountId, display: display))
        } else {
            let sub = ns.substring(with: range)
            if !sub.isEmpty { out.append(.text(sub)) }
        }
    }
    return out
}

/// True if there's nothing worth posting (no text, no mentions, no images).
func draftIsEmpty(_ attributed: NSAttributedString) -> Bool {
    draftSegments(from: attributed).allSatisfy {
        if case .text(let text) = $0 {
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return false
    }
}

// MARK: - Inline image attachments

/// Build an attributed string holding one inline image attachment, sized to a
/// thumbnail and tagged with the raw bytes so it can be read back for upload.
private func imageAttributed(_ image: IssueDetailViewModel.PastedImage) -> NSAttributedString {
    let attachment = NSTextAttachment()
    #if os(macOS)
    let platformImage = NSImage(data: image.data)
    attachment.image = platformImage
    let pixelSize = platformImage?.size ?? CGSize(width: 120, height: 90)
    #else
    let platformImage = UIImage(data: image.data)
    attachment.image = platformImage
    let pixelSize = platformImage?.size ?? CGSize(width: 120, height: 90)
    #endif
    attachment.bounds = CGRect(origin: .zero, size: thumbnailSize(for: pixelSize))

    let string = NSMutableAttributedString(attachment: attachment)
    string.addAttributes(
        [
            .balmImageData: image.data,
            .balmImageName: image.filename,
            .balmImageMime: image.mimeType ?? "image/png"
        ],
        range: NSRange(location: 0, length: string.length)
    )
    return string
}

/// Scale a pasted image down to a tidy inline thumbnail (cap height ~72pt).
private func thumbnailSize(for size: CGSize) -> CGSize {
    let maxHeight: CGFloat = 72
    let maxWidth: CGFloat = 220
    guard size.width > 0, size.height > 0 else { return CGSize(width: 120, height: 72) }
    let scale = min(maxWidth / size.width, maxHeight / size.height, 1)
    return CGSize(width: size.width * scale, height: size.height * scale)
}

/// Read an image off the system clipboard, if any, as a `PastedImage`.
func clipboardPastedImage() -> IssueDetailViewModel.PastedImage? {
    func make(_ data: Data, _ ext: String, _ mime: String) -> IssueDetailViewModel.PastedImage {
        IssueDetailViewModel.PastedImage(
            data: data,
            filename: "pasted-\(UUID().uuidString.prefix(8)).\(ext)",
            mimeType: mime
        )
    }
    #if os(macOS)
    let pb = NSPasteboard.general
    if let data = pb.data(forType: .png) { return make(data, "png", "image/png") }
    // Robust catch-all: let NSImage read whatever representation is present
    // (screenshots, copied images from any app), then normalise to PNG.
    if let image = NSImage(pasteboard: pb),
       let tiff = image.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        return make(png, "png", "image/png")
    }
    if let urls = pb.readObjects(forClasses: [NSURL.self]) as? [URL] {
        let exts = ["png", "jpg", "jpeg", "gif", "tiff", "heic", "webp"]
        for url in urls where exts.contains(url.pathExtension.lowercased()) {
            if let data = try? Data(contentsOf: url) {
                let ext = url.pathExtension.lowercased()
                return make(data, ext, "image/\(ext == "jpg" ? "jpeg" : ext)")
            }
        }
    }
    return nil
    #else
    if let image = UIPasteboard.general.image, let data = image.pngData() {
        return make(data, "png", "image/png")
    }
    return nil
    #endif
}

// MARK: - Platform colours / fonts

#if os(macOS)
private func bodyFont() -> NSFont { NSFont.preferredFont(forTextStyle: .body) }
private func plainColor() -> NSColor { .labelColor }
private func mentionColor() -> NSColor { .controlAccentColor }
#else
private func bodyFont() -> UIFont { UIFont.preferredFont(forTextStyle: .body) }
private func plainColor() -> UIColor { .label }
private func mentionColor() -> UIColor { .link }
#endif

private func plainAttributes() -> [NSAttributedString.Key: Any] {
    [.font: bodyFont(), .foregroundColor: plainColor()]
}

private func mentionAttributes(accountId: String) -> [NSAttributedString.Key: Any] {
    [
        .font: bodyFont(),
        .foregroundColor: mentionColor(),
        .balmMention: accountId
    ]
}

// MARK: - SwiftUI bridge

/// A native text editor (NSTextView / UITextView) that detects `@mention`
/// tokens as you type and lets the parent drive an autocomplete dropdown.
/// Mentions are stored as attributed runs carrying the accountId, so the parent
/// can read them back as `[CommentInline]` for ADF authoring.
struct MentionTextView: View {
    @Binding var text: NSAttributedString
    var controller: MentionController
    /// Whether the suggestion dropdown is currently showing — gates whether
    /// ↑/↓/Return/Esc are stolen from the editor for list navigation.
    var suggestionsActive: Bool
    var onQueryChange: (MentionQuery?) -> Void
    var onMoveSelection: (Int) -> Void
    var highlightedUser: () -> JiraUser?
    var onCancel: () -> Void

    var body: some View {
        Bridge(
            text: $text,
            controller: controller,
            suggestionsActive: suggestionsActive,
            onQueryChange: onQueryChange,
            onMoveSelection: onMoveSelection,
            highlightedUser: highlightedUser,
            onCancel: onCancel
        )
    }
}

#if os(macOS)
private struct Bridge: NSViewRepresentable {
    @Binding var text: NSAttributedString
    var controller: MentionController
    var suggestionsActive: Bool
    var onQueryChange: (MentionQuery?) -> Void
    var onMoveSelection: (Int) -> Void
    var highlightedUser: () -> JiraUser?
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        let textView = PasteImageTextView()
        // Opt into TextKit 1: TextKit 2 (the macOS 13+ default) doesn't render
        // an NSTextAttachment whose `image` is set the plain way, so inline
        // image thumbnails would be invisible. Touching `layoutManager`
        // migrates the view to the TextKit 1 stack, which draws them.
        _ = textView.layoutManager
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.allowsUndo = true
        textView.font = bodyFont()
        textView.typingAttributes = plainAttributes()
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        scroll.documentView = textView

        context.coordinator.textView = textView
        let coordinator = context.coordinator
        controller.perform = { [weak coordinator] user in coordinator?.insertMention(user) }
        controller.performImage = { [weak coordinator] image in coordinator?.insertImage(image) }
        textView.onPasteImage = { [weak coordinator] in coordinator?.handlePasteImage() ?? false }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scroll.documentView as? NSTextView else { return }
        if text.string != textView.string {
            textView.textStorage?.setAttributedString(text)
            textView.typingAttributes = plainAttributes()
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: Bridge
        weak var textView: NSTextView?
        private var lastScan: MentionScan?

        init(_ parent: Bridge) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            pushUp(textView)
            detect(textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else { return }
            detect(textView)
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard parent.suggestionsActive else { return false }
            switch selector {
            case #selector(NSResponder.moveDown(_:)):
                parent.onMoveSelection(1); return true
            case #selector(NSResponder.moveUp(_:)):
                parent.onMoveSelection(-1); return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel(); return true
            case #selector(NSResponder.insertNewline(_:)),
                 #selector(NSResponder.insertTab(_:)):
                if let user = parent.highlightedUser() { insertMention(user); return true }
                return false
            default:
                return false
            }
        }

        private func detect(_ textView: NSTextView) {
            let caret = textView.selectedRange().location
            if let scan = scanMention(in: textView.string as NSString, caret: caret) {
                lastScan = scan
                parent.onQueryChange(MentionQuery(text: scan.query, anchor: anchorRect(for: scan.tokenRange.location, in: textView)))
            } else {
                lastScan = nil
                parent.onQueryChange(nil)
            }
        }

        func insertMention(_ user: JiraUser) {
            guard let textView, let scan = lastScan, let storage = textView.textStorage else { return }
            let run = NSMutableAttributedString(
                string: "@\(user.displayName)",
                attributes: mentionAttributes(accountId: user.accountId)
            )
            run.append(NSAttributedString(string: " ", attributes: plainAttributes()))
            storage.replaceCharacters(in: scan.tokenRange, with: run)
            let caret = scan.tokenRange.location + run.length
            textView.setSelectedRange(NSRange(location: caret, length: 0))
            textView.typingAttributes = plainAttributes()
            lastScan = nil
            pushUp(textView)
            parent.onQueryChange(nil)
        }

        func insertImage(_ image: IssueDetailViewModel.PastedImage) {
            guard let textView, let storage = textView.textStorage else { return }
            let range = textView.selectedRange()
            let attachment = imageAttributed(image)
            storage.replaceCharacters(in: range, with: attachment)
            let caret = range.location + attachment.length
            textView.setSelectedRange(NSRange(location: caret, length: 0))
            textView.typingAttributes = plainAttributes()
            pushUp(textView)
        }

        /// Returns true if an image was on the clipboard and got inserted, so
        /// the text view skips its default text paste.
        func handlePasteImage() -> Bool {
            guard let image = clipboardPastedImage() else { return false }
            insertImage(image)
            return true
        }

        private func pushUp(_ textView: NSTextView) {
            parent.text = NSAttributedString(attributedString: textView.attributedString())
        }

        private func anchorRect(for location: Int, in textView: NSTextView) -> CGRect {
            guard let lm = textView.layoutManager, let tc = textView.textContainer else { return .zero }
            let glyph = lm.glyphRange(forCharacterRange: NSRange(location: location, length: 0), actualCharacterRange: nil)
            var rect = lm.boundingRect(forGlyphRange: glyph, in: tc)
            rect.origin.x += textView.textContainerOrigin.x
            rect.origin.y += textView.textContainerOrigin.y
            rect.origin.y -= textView.visibleRect.origin.y
            return rect
        }
    }
}

/// NSTextView that diverts `⌘V` to an image handler when the clipboard holds
/// an image, falling back to normal text paste otherwise.
private final class PasteImageTextView: NSTextView {
    var onPasteImage: (() -> Bool)?

    override func paste(_ sender: Any?) {
        if onPasteImage?() == true { return }
        super.paste(sender)
    }

    /// A plain NSTextView reports Paste as invalid when the clipboard holds
    /// only an image, which disables the menu item *and* swallows the ⌘V key
    /// equivalent before `paste(_:)` runs. Re-enable it whenever an image is
    /// present so our override gets the chance to handle it.
    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(NSText.paste(_:)),
           NSPasteboard.general.canReadObject(forClasses: [NSImage.self], options: nil) {
            return true
        }
        return super.validateMenuItem(menuItem)
    }
}
#else
private struct Bridge: UIViewRepresentable {
    @Binding var text: NSAttributedString
    var controller: MentionController
    var suggestionsActive: Bool
    var onQueryChange: (MentionQuery?) -> Void
    var onMoveSelection: (Int) -> Void
    var highlightedUser: () -> JiraUser?
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let textView = PasteImageTextView()
        textView.delegate = context.coordinator
        textView.font = bodyFont()
        textView.typingAttributes = plainAttributes()
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 6, left: 4, bottom: 6, right: 4)
        context.coordinator.textView = textView
        let coordinator = context.coordinator
        controller.perform = { [weak coordinator] user in coordinator?.insertMention(user) }
        controller.performImage = { [weak coordinator] image in coordinator?.insertImage(image) }
        textView.onPasteImage = { [weak coordinator] in coordinator?.handlePasteImage() ?? false }
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        if text.string != textView.text {
            textView.attributedText = text
            textView.typingAttributes = plainAttributes()
        }
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: Bridge
        weak var textView: UITextView?
        private var lastScan: MentionScan?

        init(_ parent: Bridge) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            pushUp(textView)
            detect(textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            detect(textView)
        }

        private func detect(_ textView: UITextView) {
            let caret = textView.selectedRange.location
            if let scan = scanMention(in: textView.text as NSString, caret: caret) {
                lastScan = scan
                parent.onQueryChange(MentionQuery(text: scan.query, anchor: anchorRect(for: scan.tokenRange.location, in: textView)))
            } else {
                lastScan = nil
                parent.onQueryChange(nil)
            }
        }

        func insertMention(_ user: JiraUser) {
            guard let textView, let scan = lastScan else { return }
            let storage = NSMutableAttributedString(attributedString: textView.attributedText)
            let run = NSMutableAttributedString(
                string: "@\(user.displayName)",
                attributes: mentionAttributes(accountId: user.accountId)
            )
            run.append(NSAttributedString(string: " ", attributes: plainAttributes()))
            storage.replaceCharacters(in: scan.tokenRange, with: run)
            textView.attributedText = storage
            let caret = scan.tokenRange.location + run.length
            textView.selectedRange = NSRange(location: caret, length: 0)
            textView.typingAttributes = plainAttributes()
            lastScan = nil
            pushUp(textView)
            parent.onQueryChange(nil)
        }

        func insertImage(_ image: IssueDetailViewModel.PastedImage) {
            guard let textView else { return }
            let storage = NSMutableAttributedString(attributedString: textView.attributedText)
            let range = textView.selectedRange
            storage.replaceCharacters(in: range, with: imageAttributed(image))
            textView.attributedText = storage
            let caret = range.location + 1
            textView.selectedRange = NSRange(location: caret, length: 0)
            textView.typingAttributes = plainAttributes()
            pushUp(textView)
        }

        func handlePasteImage() -> Bool {
            guard let image = clipboardPastedImage() else { return false }
            insertImage(image)
            return true
        }

        private func pushUp(_ textView: UITextView) {
            parent.text = NSAttributedString(attributedString: textView.attributedText)
        }

        private func anchorRect(for location: Int, in textView: UITextView) -> CGRect {
            guard let start = textView.position(from: textView.beginningOfDocument, offset: location),
                  let range = textView.textRange(from: start, to: start) else { return .zero }
            var rect = textView.firstRect(for: range)
            rect.origin.y -= textView.contentOffset.y
            return rect
        }
    }
}

/// UITextView that diverts paste to an image handler when the clipboard holds
/// an image, falling back to normal text paste otherwise.
private final class PasteImageTextView: UITextView {
    var onPasteImage: (() -> Bool)?

    override func paste(_ sender: Any?) {
        if onPasteImage?() == true { return }
        super.paste(sender)
    }

    /// Enable Paste when the pasteboard holds an image, so the command/⌘V is
    /// offered and reaches our `paste(_:)` override.
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)), UIPasteboard.general.hasImages {
            return true
        }
        return super.canPerformAction(action, withSender: sender)
    }
}
#endif
