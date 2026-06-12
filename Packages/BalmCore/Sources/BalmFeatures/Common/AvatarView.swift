import SwiftUI
import BalmModels
import BalmDesignSystem

struct AvatarView: View {
    @Environment(\.balmTheme) private var theme
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
            .font(.system(size: max(size * 0.42, 10), weight: .semibold))
            .frame(width: size, height: size)
            .background(Circle().fill(theme.palette.secondary))
            .foregroundStyle(theme.palette.foreground)
    }

    private var initials: String {
        let n = name ?? "?"
        let parts = n.split(separator: " ")
        let i = parts.prefix(2).compactMap { $0.first.map(String.init) }
        return i.isEmpty ? "?" : i.joined().uppercased()
    }
}

extension JiraUserSummary {
    var avatarURL: URL? { avatarUrls?.bestAvailable }
}
