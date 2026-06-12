import SwiftUI

public struct BalmChip: View {
    @Environment(\.balmTheme) private var theme
    public let text: String
    public let tint: Color?

    public init(_ text: String, tint: Color? = nil) {
        self.text = text
        self.tint = tint
    }

    public var body: some View {
        let base = tint ?? theme.palette.mutedForeground
        Text(text)
            .font(theme.typography.caption.weight(.medium))
            .padding(.horizontal, theme.spacing.s)
            .padding(.vertical, theme.spacing.xs)
            .foregroundStyle(base)
            .background(base.opacity(0.14))
            .overlay(
                RoundedRectangle(cornerRadius: theme.radii.sm, style: .continuous)
                    .strokeBorder(base.opacity(0.30), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: theme.radii.sm, style: .continuous))
    }
}
