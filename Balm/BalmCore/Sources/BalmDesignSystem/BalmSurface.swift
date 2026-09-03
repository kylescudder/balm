import SwiftUI

#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// The two system surfaces Balm draws on when a `List` or `Form` is not doing
/// it already. Both are the platform's own dynamic colours, so they follow
/// appearance, vibrancy and accessibility settings without any custom values.
public enum BalmSurface {
    /// A raised card on the window: white in light, elevated grey in dark.
    public static var card: Color {
        #if canImport(AppKit)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }

    /// The window or grouped background a card sits on.
    public static var window: Color {
        #if canImport(AppKit)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(uiColor: .systemGroupedBackground)
        #endif
    }
}
