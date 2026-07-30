import SwiftUI

public struct BalmTheme: Sendable {
    public let palette: BalmPalette
    public let spacing: Spacing
    public let radii: Radii
    public let typography: Typography
}

public extension BalmTheme {
    static let `default` = BalmTheme(
        palette: .balm,
        spacing: .default,
        radii: .default,
        typography: .default
    )
}

private struct BalmThemeKey: EnvironmentKey {
    static let defaultValue: BalmTheme = .default
}

public extension EnvironmentValues {
    var balmTheme: BalmTheme {
        get { self[BalmThemeKey.self] }
        set { self[BalmThemeKey.self] = newValue }
    }
}

public extension View {
    /// Installs the design tokens in the environment. Wrap the root of each
    /// scene with this. Colours come from the native system palette, so the
    /// app picks up macOS/iOS dark mode and the user's accent automatically.
    func themed() -> some View {
        environment(\.balmTheme, .default)
    }
}
