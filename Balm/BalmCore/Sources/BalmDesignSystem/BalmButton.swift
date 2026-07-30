import SwiftUI

public struct BalmPrimaryButtonStyle: ButtonStyle {
    @Environment(\.balmTheme) private var theme

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(theme.typography.body.weight(.semibold))
            .padding(.horizontal, theme.spacing.l)
            .padding(.vertical, theme.spacing.s)
            .foregroundStyle(theme.palette.primaryForeground)
            .background(theme.palette.primary.opacity(configuration.isPressed ? 0.8 : 1))
            .clipShape(RoundedRectangle(cornerRadius: theme.radii.md, style: .continuous))
    }
}

public struct BalmSecondaryButtonStyle: ButtonStyle {
    @Environment(\.balmTheme) private var theme

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(theme.typography.body.weight(.medium))
            .padding(.horizontal, theme.spacing.l)
            .padding(.vertical, theme.spacing.s)
            .foregroundStyle(theme.palette.foreground)
            .background(theme.palette.secondary.opacity(configuration.isPressed ? 0.7 : 1))
            .clipShape(RoundedRectangle(cornerRadius: theme.radii.md, style: .continuous))
    }
}
