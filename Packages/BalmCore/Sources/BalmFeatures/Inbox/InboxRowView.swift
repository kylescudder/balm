import SwiftUI
import BalmModels
import BalmDesignSystem

struct InboxRowView: View {
    @Environment(\.balmTheme) private var theme
    let notification: BalmNotification

    var body: some View {
        HStack(alignment: .top, spacing: theme.spacing.m) {
            unreadDot
            Image(systemName: symbolName)
                .foregroundStyle(theme.palette.primary)
                .frame(width: 20, alignment: .center)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: theme.spacing.xs) {
                HStack(spacing: theme.spacing.s) {
                    Text(notification.issueKey)
                        .font(theme.typography.caption.monospaced())
                        .foregroundStyle(theme.palette.mutedForeground)
                    Text(kindLabel)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.palette.mutedForeground)
                }
                // Unread reads like Mail: bold at full strength; read rows
                // drop to regular weight (plus the whole-row dim below).
                Text(notification.issueSummary)
                    .font(theme.typography.body.weight(notification.isRead ? .regular : .semibold))
                    .foregroundStyle(theme.palette.foreground)
                    .lineLimit(2)
                if let excerpt = excerptText {
                    Text(excerpt)
                        .font(theme.typography.callout)
                        .foregroundStyle(theme.palette.mutedForeground)
                        .lineLimit(2)
                }
                HStack(spacing: theme.spacing.xs) {
                    if let actor = notification.actorDisplayName {
                        Text(actor)
                            .font(theme.typography.caption.weight(.semibold))
                            .foregroundStyle(theme.palette.foreground)
                        Text("·")
                            .foregroundStyle(theme.palette.mutedForeground)
                    }
                    Text(timestampLabel)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.palette.mutedForeground)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, theme.spacing.xs)
        .opacity(notification.isRead ? 0.65 : 1.0)
    }

    /// Mirrors `BoardColumnView`'s status dot — a filled 8pt circle marks
    /// unread, an invisible one keeps read rows aligned to the same inset.
    private var unreadDot: some View {
        Circle()
            .fill(notification.isRead ? Color.clear : theme.palette.primary)
            .frame(width: 8, height: 8)
            .padding(.top, 6)
    }

    private var symbolName: String {
        switch notification.kind {
        case .assignedToYou: return "person.crop.circle.badge.checkmark"
        case .statusChanged: return "arrow.right.circle"
        case .commented: return "text.bubble"
        case .mentioned: return "at.circle"
        case .fieldUpdated: return "pencil.circle"
        }
    }

    private var kindLabel: String {
        switch notification.kind {
        case .assignedToYou:
            return "Assigned to you"
        case .statusChanged(let from, let to):
            if let from, let to { return "\(from) → \(to)" }
            if let to { return "Moved to \(to)" }
            return "Status changed"
        case .commented:
            return "New comment"
        case .mentioned:
            return "Mentioned you"
        case .fieldUpdated(let field):
            return "\(field) updated"
        }
    }

    private var excerptText: String? {
        switch notification.kind {
        case .commented(let excerpt), .mentioned(let excerpt):
            return excerpt
        default:
            return nil
        }
    }

    private var timestampLabel: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: notification.date, relativeTo: Date())
    }
}
