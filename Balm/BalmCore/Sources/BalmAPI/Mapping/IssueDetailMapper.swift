import Foundation
import BalmModels

public enum IssueDetailMapper {
    /// Produces both the domain `JiraIssue` and the `JiraIssueDetails` bundle
    /// (comments, attachments, changelog, issue links) from a single raw issue
    /// fetched with `expand=changelog&fields=*all`.
    public static func decode(_ raw: RawJiraIssue, instanceFieldID: String? = nil) -> (JiraIssue, JiraIssueDetails) {
        let issue = JiraIssueMapper.issue(from: raw, instanceFieldID: instanceFieldID)
        let details = JiraIssueDetails(
            attachments: mapAttachments(raw.fields.attachment ?? []),
            comments: mapComments(raw.fields.comment?.comments ?? []),
            changelog: mapChangelog(raw.changelog?.histories ?? []),
            issueLinks: mapIssueLinks(raw.fields.issuelinks ?? [])
        )
        return (issue, details)
    }

    // MARK: - Attachments

    private static func mapAttachments(_ raw: [RawJiraAttachment]) -> [JiraAttachmentMeta] {
        raw.map { r in
            JiraAttachmentMeta(
                id: r.id,
                filename: r.filename,
                size: r.size,
                mimeType: r.mimeType,
                isImage: r.mimeType?.hasPrefix("image/") ?? hasImageExtension(r.filename),
                content: r.content,
                thumbnail: r.thumbnail,
                created: r.created
            )
        }
    }

    private static func hasImageExtension(_ filename: String) -> Bool {
        let lower = filename.lowercased()
        return [".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".svg"].contains { lower.hasSuffix($0) }
    }

    // MARK: - Comments

    private static func mapComments(_ raw: [RawJiraComment]) -> [JiraComment] {
        raw.map(comment(from:))
    }

    public static func comment(from r: RawJiraComment) -> JiraComment {
        JiraComment(
            id: r.id,
            author: r.author,
            created: r.created,
            updated: r.updated,
            body: r.renderedBody ?? plainTextFromBody(r.body?.raw),
            bodyADF: (r.body?.raw.isEmpty ?? true) ? nil : r.body?.raw
        )
    }

    /// Quick-and-cheap plain text fallback when the renderer hasn't yet seen ADF.
    /// Used only for sorting/preview — the full ADF view renders the rich payload.
    public static func plainTextFromBody(_ data: Data?) -> String {
        guard let data, !data.isEmpty else { return "" }
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return "" }
        var out = ""
        walkText(json, into: &out)
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func walkText(_ node: Any, into out: inout String) {
        if let dict = node as? [String: Any] {
            if let text = dict["text"] as? String { out += text }
            if let content = dict["content"] as? [Any] {
                for child in content {
                    walkText(child, into: &out)
                    if (dict["type"] as? String) == "paragraph" { out += "\n" }
                }
            }
        }
    }

    // MARK: - Changelog

    private static func mapChangelog(_ raw: [RawJiraChangelogEntry]) -> [JiraChangeLogItem] {
        raw.map { entry in
            JiraChangeLogItem(
                id: entry.id,
                author: entry.author,
                created: entry.created,
                items: entry.items
            )
        }
    }

    // MARK: - Issue links

    private static func mapIssueLinks(_ raw: [RawJiraIssueLink]) -> [JiraIssueLink] {
        raw.compactMap { link in
            let direction: JiraIssueLink.Direction
            let other: RawJiraIssueLink.LinkedIssue
            let relationship: String

            // Jira reports the *other* issue in one field; its presence tells us
            // the current issue's role. `inwardIssue` populated → the other issue
            // is the inward side, so *this* issue is the outward side (and vice
            // versa). Phrase + direction are from this issue's perspective.
            if let inward = link.inwardIssue {
                direction = .outward
                other = inward
                relationship = link.type.outward
            } else if let outward = link.outwardIssue {
                direction = .inward
                other = outward
                relationship = link.type.inward
            } else {
                return nil
            }

            return JiraIssueLink(
                id: link.id,
                type: link.type,
                direction: direction,
                relationship: relationship,
                issue: JiraIssueLink.LinkedIssue(
                    key: other.key,
                    summary: other.fields?.summary ?? other.key,
                    status: other.fields?.status,
                    issueType: other.fields?.issuetype,
                    priority: other.fields?.priority
                )
            )
        }
    }
}
