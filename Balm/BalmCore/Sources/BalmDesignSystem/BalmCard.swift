import SwiftUI

public struct BalmCard<Content: View>: View {
    @Environment(\.balmTheme) private var theme
    private let content: () -> Content
    private let padding: CGFloat?

    public init(padding: CGFloat? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.content = content
        self.padding = padding
    }

    public var body: some View {
        content()
            .padding(padding ?? theme.spacing.l)
            .background(theme.palette.card)
            .clipShape(RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous)
                    .strokeBorder(theme.palette.border, lineWidth: 1)
            )
    }
}
