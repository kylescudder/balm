import SwiftUI
import BalmModels

struct AvatarView: View {
    let name: String?
    let avatarURL: URL?
    let size: CGFloat

    init(name: String?, avatarURL: URL? = nil, size: CGFloat = 28) {
        self.name = name
        self.avatarURL = avatarURL
        self.size = size
    }

    var body: some View {
        Group {
            if let url = avatarURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        initialsView
                    }
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
            } else {
                initialsView
            }
        }
        .accessibilityLabel(name ?? "User avatar")
    }

    private var initialsView: some View {
        Text(initials)
            .font(.system(size: max(size * 0.42, 9), weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
            .background(.quaternary, in: Circle())
    }

    private var initials: String {
        let n = name ?? "?"
        let parts = n.split(separator: " ")
        let i = parts.prefix(2).compactMap { $0.first.map(String.init) }
        return i.isEmpty ? "?" : i.joined().uppercased()
    }
}

/// The dashed ring that stands in for "unassigned" at avatar size, so rows
/// keep their alignment and the gap reads as a deliberate empty slot.
struct UnassignedAvatar: View {
    var size: CGFloat = 20

    var body: some View {
        Circle()
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            .foregroundStyle(.tertiary)
            .frame(width: size, height: size)
            .accessibilityLabel("Unassigned")
    }
}

extension JiraUserSummary {
    var avatarURL: URL? { avatarUrls?.bestAvailable }
}
