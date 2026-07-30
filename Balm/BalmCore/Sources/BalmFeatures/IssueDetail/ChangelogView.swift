import SwiftUI
import BalmModels
import BalmDesignSystem

struct ChangelogView: View {
    @Environment(\.balmTheme) private var theme
    let entries: [JiraChangeLogItem]
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: theme.spacing.m) {
                if entries.isEmpty {
                    Text("No activity yet.")
                        .font(theme.typography.callout)
                        .foregroundStyle(theme.palette.mutedForeground)
                } else {
                    ForEach(entries) { entry in
                        EntryRow(entry: entry)
                    }
                }
            }
            .padding(.top, theme.spacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            SectionHeading("Activity (\(entries.count))")
        }
        .tint(theme.palette.mutedForeground)
    }
}

private struct EntryRow: View {
    @Environment(\.balmTheme) private var theme
    let entry: JiraChangeLogItem

    var body: some View {
        HStack(alignment: .top, spacing: theme.spacing.s) {
            AvatarView(name: entry.author.displayName, size: 22)
            VStack(alignment: .leading, spacing: theme.spacing.xs) {
                Text("\(entry.author.displayName) \(formatItems())")
                    .font(theme.typography.body)
                    .foregroundStyle(theme.palette.foreground)
                Text(timestamp)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.palette.mutedForeground)
            }
        }
    }

    private func formatItems() -> String {
        entry.items.map { item -> String in
            let raw = { (s: String?) -> String in s.map { "\"\($0)\"" } ?? "—" }
            // Field-aware display — only "status" warrants normalisation so
            // "AWAITING TESTING" → "Awaiting Testing" in the changelog text.
            if item.field.lowercased() == "status" {
                let from = item.fromString.map { "\"\(StatusNormaliser.normalise($0))\"" } ?? "—"
                let to = item.toString.map { "\"\(StatusNormaliser.normalise($0))\"" } ?? "—"
                return "changed \(item.field) from \(from) to \(to)"
            }
            return "changed \(item.field) from \(raw(item.fromString)) to \(raw(item.toString))"
        }.joined(separator: "; ")
    }

    private var timestamp: String {
        guard let date = entry.created else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
