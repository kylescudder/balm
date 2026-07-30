import SwiftUI

/// Balm design palette. Warm, restorative, eucalyptus-sage led — the calm
/// antidote to the cramped corporate blue of the tool it replaces. Every
/// token adapts to light/dark via `Color.adaptive(light:dark:)`.
public struct BalmPalette: Sendable {
    public let background: Color
    public let foreground: Color

    public let card: Color
    public let cardForeground: Color
    public let popover: Color
    public let popoverForeground: Color

    public let primary: Color
    public let primaryForeground: Color
    public let secondary: Color
    public let secondaryForeground: Color
    public let muted: Color
    public let mutedForeground: Color
    public let accent: Color
    public let accentForeground: Color
    public let destructive: Color
    public let destructiveForeground: Color

    public let border: Color
    public let input: Color
    public let ring: Color

    public let chart1: Color
    public let chart2: Color
    public let chart3: Color
    public let chart4: Color
    public let chart5: Color

    public let sidebarBackground: Color
    public let sidebarForeground: Color
    public let sidebarPrimary: Color
    public let sidebarPrimaryForeground: Color
    public let sidebarAccent: Color
    public let sidebarAccentForeground: Color
    public let sidebarBorder: Color
    public let sidebarRing: Color
}

public extension BalmPalette {
    /// The Balm palette. One instance; each colour resolves per appearance.
    static let balm = BalmPalette(
        // Warm off-white paper (light) / deep slate-green charcoal (dark).
        background:              .adaptive(light: 0xFAF6EE, dark: 0x191B1A),
        foreground:              .adaptive(light: 0x2C332E, dark: 0xECEAE0),

        // Raised surfaces sit a touch warmer/lighter than the page.
        card:                    .adaptive(light: 0xF2ECE0, dark: 0x222423),
        cardForeground:          .adaptive(light: 0x2C332E, dark: 0xECEAE0),
        popover:                 .adaptive(light: 0xF6F1E7, dark: 0x222423),
        popoverForeground:       .adaptive(light: 0x2C332E, dark: 0xECEAE0),

        // Eucalyptus sage is the brand accent.
        primary:                 .adaptive(light: 0x5E7A66, dark: 0x8AA890),
        primaryForeground:       .adaptive(light: 0xFAF6EE, dark: 0x191B1A),
        secondary:               .adaptive(light: 0xE7E0D1, dark: 0x2C2F2D),
        secondaryForeground:     .adaptive(light: 0x2C332E, dark: 0xECEAE0),
        muted:                   .adaptive(light: 0xEDE7D9, dark: 0x242625),
        mutedForeground:         .adaptive(light: 0x6E756D, dark: 0x969C96),
        accent:                  .adaptive(light: 0x6E8A76, dark: 0x8AA890),
        accentForeground:        .adaptive(light: 0xFAF6EE, dark: 0x191B1A),

        // Even "destructive" is a soft clay, never a screaming red.
        destructive:             .adaptive(light: 0xB5705F, dark: 0xCC8A78),
        destructiveForeground:   .adaptive(light: 0xFAF6EE, dark: 0x191B1A),

        border:                  .adaptive(light: 0xE2DACB, dark: 0x313431),
        input:                   .adaptive(light: 0xE2DACB, dark: 0x313431),
        ring:                    .adaptive(light: 0x6E8A76, dark: 0x8AA890),

        // Muted, desaturated status accents — calm even when something's wrong.
        chart1:                  .adaptive(light: 0x7B96B0, dark: 0x93AECB), // dusty blue
        chart2:                  .adaptive(light: 0x6E8A76, dark: 0x8AA890), // sage
        chart3:                  .adaptive(light: 0x6E9A98, dark: 0x88B6B3), // muted teal
        chart4:                  .adaptive(light: 0xC98F5E, dark: 0xDBA877), // warm clay
        chart5:                  .adaptive(light: 0x5E8A66, dark: 0x83B189), // green

        sidebarBackground:       .adaptive(light: 0xF2ECE0, dark: 0x151716),
        sidebarForeground:       .adaptive(light: 0x2C332E, dark: 0xECEAE0),
        sidebarPrimary:          .adaptive(light: 0x5E7A66, dark: 0x8AA890),
        sidebarPrimaryForeground: .adaptive(light: 0xFAF6EE, dark: 0x191B1A),
        sidebarAccent:           .adaptive(light: 0xE7E0D1, dark: 0x2C2F2D),
        sidebarAccentForeground: .adaptive(light: 0x2C332E, dark: 0xECEAE0),
        sidebarBorder:           .adaptive(light: 0xE2DACB, dark: 0x313431),
        sidebarRing:             .adaptive(light: 0x6E8A76, dark: 0x8AA890)
    )
}
