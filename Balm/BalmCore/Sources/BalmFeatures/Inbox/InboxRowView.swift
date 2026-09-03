import SwiftUI
import BalmModels
import BalmDesignSystem

struct InboxRowView: View {
    @Environment(\.balmTheme) private var theme
    let notification: BalmNotification

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            unreadDot
            Image(systemName: symbolName)
                .foregroundStyle(theme.palette.accent)
                .frame(width: 18, alignment: .center)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 10) {
                    Text(notification.issueKey)
                        .monospacedDigit()
                    Text(kindLabel)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                // Unread reads like Mail: bold at full strength; read rows
                // drop to regular weight (plus the whole-row dim below).
                Text(notification.issueSummary)
                    .font(.body.weight(notification.isRead ? .regular : .semibold))
                    .lineLimit(2)
                if let excerpt = excerptText {
                    Text(excerpt)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 8) {
                    if let actor = notification.actorDisplayName {
                        Text(actor)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                    }
                    Text(timestampLabel)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .opacity(notification.isRead ? 0.7 : 1.0)
        .accessibilityElement(children: .combine)
    }

    /// A filled 8 pt dot marks unread; an invisible one keeps read rows aligned.
    private var unreadDot: some View {
        Circle()
            .fill(notification.isRead ? Color.clear : theme.palette.accent)
            .frame(width: 8, height: 8)
            .padding(.top, 5)
            .accessibilityLabel(notification.isRead ? "" : "Unread")
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
            if let from, let to {
                return "\(StatusNormaliser.normalise(from)) to \(StatusNormaliser.normalise(to))"
            }
            if let to { return "Moved to \(StatusNormaliser.normalise(to))" }
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
