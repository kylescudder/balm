import AuthenticationServices
import SwiftUI

/// Bridges between SwiftUI and AuthenticationServices' anchor requirement.
/// On macOS this is an NSWindow; on iOS/iPadOS, a UIWindow.
public struct ASPresentationAnchorBridge: Sendable {
    public let anchor: ASPresentationAnchor

    public init(anchor: ASPresentationAnchor) { self.anchor = anchor }
}

#if canImport(UIKit)
import UIKit

public extension ASPresentationAnchorBridge {
    @MainActor
    static func resolveFromActiveScene() -> ASPresentationAnchorBridge {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })
            ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first
            ?? UIWindow()
        return ASPresentationAnchorBridge(anchor: window)
    }
}
#endif

#if canImport(AppKit)
import AppKit

public extension ASPresentationAnchorBridge {
    @MainActor
    static func resolveFromActiveScene() -> ASPresentationAnchorBridge {
        let window = NSApp.keyWindow ?? NSApp.windows.first ?? NSWindow()
        return ASPresentationAnchorBridge(anchor: window)
    }
}
#endif
