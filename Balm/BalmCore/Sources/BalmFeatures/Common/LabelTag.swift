import SwiftUI
import BalmModels

/// A quiet tag for a Jira label: caption text on a quaternary capsule, no
/// border. The glyph carries status, so labels never compete with it.
struct LabelTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .lineLimit(1)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
            .background(.quaternary, in: Capsule())
    }
}

/// Jira's own priority icon at row size. Nothing is drawn when the priority
/// has no icon, so rows without one keep their alignment through the fixed
/// frame.
struct PriorityIcon: View {
    let priority: JiraPriority
    var size: CGFloat = 14

    var body: some View {
        Group {
            if let url = priority.iconUrl {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFit()
                    } else {
                        Color.clear
                    }
                }
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Priority \(priority.name)")
    }
}

/// The two-letter project badge used in sidebars. Filled with the accent when
/// it is the active project.
struct ProjectKeyBadge: View {
    let key: String
    var isActive = false
    var size: CGFloat = 18

    var body: some View {
        Text(String(key.prefix(2)).uppercased())
            .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
            .frame(width: size, height: size)
            .foregroundStyle(isActive ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            .background(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary),
                        in: RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
            .accessibilityHidden(true)
    }
}
