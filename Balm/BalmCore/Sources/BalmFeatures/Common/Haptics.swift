import SwiftUI

#if canImport(UIKit) && !os(macOS)
import UIKit
#endif

/// Single, cross-platform hook for tactile feedback. macOS is a no-op.
public enum Haptics {
    public enum Style: Sendable {
        case light, medium, success, warning, error, selection
    }

    @MainActor
    public static func fire(_ style: Style) {
        #if canImport(UIKit) && !os(macOS)
        switch style {
        case .light:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .medium:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .error:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .selection:
            UISelectionFeedbackGenerator().selectionChanged()
        }
        #endif
    }
}
