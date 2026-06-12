import Foundation

/// One inline fragment of a comment body: plain text or an @mention. The API
/// layer turns these into ADF `text` / `mention` nodes when posting, so a
/// mention actually notifies the person in Jira.
public enum CommentInline: Sendable, Hashable {
    case text(String)
    case mention(accountId: String, display: String)
}

public extension Array where Element == CommentInline {
    /// Flatten to plain text (mentions render as "@Display"). Used for the
    /// optimistic comment body shown before the server echoes ADF back.
    var plainText: String {
        map {
            switch $0 {
            case .text(let text): return text
            case .mention(_, let display): return "@\(display)"
            }
        }
        .joined()
    }

    /// True when there's nothing postable (only whitespace, no mentions).
    var isBlank: Bool {
        allSatisfy {
            if case .text(let text) = $0 {
                return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return false
        }
    }
}

/// An ordered, block-aware comment body: inline runs (text / mention) plus
/// images that have already been uploaded (carrying their Media-services file
/// id). The API layer turns a run of inline segments into a paragraph and
/// breaks to a block-level `mediaSingle` whenever an image appears, so images
/// land exactly where they were placed in the composer.
public enum CommentSegment: Sendable, Hashable {
    case text(String)
    case mention(accountId: String, display: String)
    case image(mediaFileID: String)
}

public extension Array where Element == CommentSegment {
    var plainText: String {
        map {
            switch $0 {
            case .text(let text): return text
            case .mention(_, let display): return "@\(display)"
            case .image: return ""
            }
        }
        .joined()
    }
}
