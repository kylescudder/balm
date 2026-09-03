import SwiftUI

/// Balm's colour: the OS supplies every surface and text colour, Balm supplies
/// four signals. Sage is the brand accent and the colour of progress; ochre
/// means waiting on someone else; clay means blocked; grey means not started
/// or closed without doing. Each resolves per appearance through
/// `Color.adaptive(light:dark:)`.
///
/// There are deliberately no surface, card, border or "muted" tokens here.
/// Backgrounds come from `List`, `Form`, the sidebar material and
/// `BalmSurface`; text uses `.primary`, `.secondary` and `.tertiary`.
public struct BalmPalette: Sendable {
    /// The brand accent. Selection, focus, links, the primary button, unread
    /// markers, and the active and done status glyphs.
    public let accent: Color
    /// Waiting on someone else: testing, information, monitoring.
    public let waiting: Color
    /// Blocked or needing attention.
    public let blocked: Color
    /// Not started, and closed without doing. The system grey.
    public let neutral: Color

    public init(accent: Color, waiting: Color, blocked: Color, neutral: Color) {
        self.accent = accent
        self.waiting = waiting
        self.blocked = blocked
        self.neutral = neutral
    }
}

public extension BalmPalette {
    static let balm = BalmPalette(
        accent: .adaptive(light: 0x5E7A66, dark: 0x8AA890),
        waiting: .adaptive(light: 0xB08A3E, dark: 0xC9A45C),
        blocked: .adaptive(light: 0xB5705F, dark: 0xCC8A78),
        neutral: .gray
    )
}
