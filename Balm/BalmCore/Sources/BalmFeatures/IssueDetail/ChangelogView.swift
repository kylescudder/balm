import SwiftUI
import BalmModels
import BalmDesignSystem

struct ChangelogView: View {
    let entries: [JiraChangeLogItem]
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 12) {
                if entries.isEmpty {
                    Text("No activity yet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entries) { entry in
                        EntryRow(entry: entry)
                    }
                }
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            SectionHeading("Activity", count: entries.count)
        }
        .tint(.secondary)
    }
}

private struct EntryRow: View {
    let entry: JiraChangeLogItem

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            AvatarView(name: entry.author.displayName, size: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(entry.author.displayName) \(formatItems())")
                    .font(.callout)
                Text(timestamp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formatItems() -> String {
        entry.items.map { item -> String in
            let raw = { (s: String?) -> String in s.map { "\"\($0)\"" } ?? "nothing" }
            // Field-aware display: only "status" warrants normalisation so
            // "AWAITING TESTING" reads as "Awaiting Testing" in the text.
            if item.field.lowercased() == "status" {
                let from = item.fromString.map { "\"\(StatusNormaliser.normalise($0))\"" } ?? "nothing"
                let to = item.toString.map { "\"\(StatusNormaliser.normalise($0))\"" } ?? "nothing"
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
