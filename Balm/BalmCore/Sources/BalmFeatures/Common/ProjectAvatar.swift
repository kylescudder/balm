import SwiftUI
import BalmModels
import BalmDesignSystem

/// A project's own Jira avatar, loaded through the authenticated gateway and
/// cached for the session. Falls back to the two-letter key badge while
/// loading or when there is no image. The active project gets a tint ring.
struct ProjectAvatar: View {
    @Environment(AppEnvironment.self) private var env
    let project: JiraProject
    var size: CGFloat = 24
    var isActive = false

    @State private var image: Image?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
        Group {
            if let image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                ProjectKeyBadge(key: project.key, isActive: isActive, size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay {
            if isActive && image != nil {
                shape.strokeBorder(.tint, lineWidth: 1.5)
            }
        }
        .task(id: avatarURL) { await load() }
        .accessibilityHidden(true)
    }

    /// Jira serves project avatars as SVG unless asked for PNG, and neither
    /// platform decodes SVG data reliably, so the request always asks for PNG.
    private var avatarURL: URL? {
        guard let base = project.avatarUrls?.bestAvailable,
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        else { return nil }
        var items = (components.queryItems ?? []).filter { $0.name != "format" }
        items.append(URLQueryItem(name: "format", value: "png"))
        components.queryItems = items
        return components.url
    }

    private func load() async {
        guard let url = avatarURL else { image = nil; return }
        image = await ProjectAvatarCache.shared.image(for: url) { url in
            guard let data = try? await env.api.attachmentData(url: url) else { return nil }
            return decodeImage(data)?.image
        }
    }
}

/// Session cache for project avatars, deduplicating concurrent loads so a
/// project shown in the sidebar, the recent tiles and the full grid at once
/// fetches its image exactly once.
@MainActor
final class ProjectAvatarCache {
    static let shared = ProjectAvatarCache()

    private var images: [URL: Image] = [:]
    private var inFlight: [URL: Task<Image?, Never>] = [:]

    func image(for url: URL, load: @escaping @MainActor (URL) async -> Image?) async -> Image? {
        if let cached = images[url] { return cached }
        if let task = inFlight[url] { return await task.value }
        let task = Task<Image?, Never> { await load(url) }
        inFlight[url] = task
        let result = await task.value
        inFlight[url] = nil
        if let result { images[url] = result }
        return result
    }

    func reset() {
        images.removeAll()
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
    }
}
