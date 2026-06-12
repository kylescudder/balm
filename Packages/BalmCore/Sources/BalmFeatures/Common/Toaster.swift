import SwiftUI
import Observation
import BalmDesignSystem

@MainActor
@Observable
public final class Toaster {
    public struct Toast: Identifiable, Sendable, Equatable {
        public let id = UUID()
        public let message: String
        public let kind: Kind
        public init(message: String, kind: Kind) {
            self.message = message
            self.kind = kind
        }
        public enum Kind: Sendable, Equatable { case success, info, error }
    }

    public private(set) var toasts: [Toast] = []
    private let defaultDuration: TimeInterval

    public init(defaultDuration: TimeInterval = 2.5) {
        self.defaultDuration = defaultDuration
    }

    public func info(_ message: String) { show(message, kind: .info) }
    public func success(_ message: String) { show(message, kind: .success) }
    public func error(_ message: String) { show(message, kind: .error, duration: 4.0) }

    public func show(
        _ message: String,
        kind: Toast.Kind,
        duration: TimeInterval? = nil
    ) {
        let toast = Toast(message: message, kind: kind)
        toasts.append(toast)
        switch kind {
        case .success: Haptics.fire(.success)
        case .error: Haptics.fire(.error)
        case .info: break
        }
        let life = duration ?? defaultDuration
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(life))
            self?.dismiss(toast.id)
        }
    }

    public func dismiss(_ id: UUID) {
        toasts.removeAll { $0.id == id }
    }
}

struct ToastOverlayView: View {
    @Environment(\.balmTheme) private var theme
    let toaster: Toaster

    var body: some View {
        VStack(spacing: theme.spacing.s) {
            ForEach(toaster.toasts) { toast in
                ToastBubble(toast: toast)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onTapGesture { toaster.dismiss(toast.id) }
            }
        }
        .padding(theme.spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(!toaster.toasts.isEmpty)
        .animation(.spring(duration: 0.25), value: toaster.toasts.map(\.id))
    }
}

private struct ToastBubble: View {
    @Environment(\.balmTheme) private var theme
    let toast: Toaster.Toast

    var body: some View {
        HStack(spacing: theme.spacing.s) {
            Image(systemName: iconName)
                .foregroundStyle(tint)
            Text(toast.message)
                .font(theme.typography.body)
                .foregroundStyle(theme.palette.foreground)
            Spacer()
        }
        .padding(.horizontal, theme.spacing.m)
        .padding(.vertical, theme.spacing.s)
        .background(theme.palette.card)
        .overlay(
            RoundedRectangle(cornerRadius: theme.radii.md, style: .continuous)
                .strokeBorder(tint.opacity(0.4))
        )
        .clipShape(RoundedRectangle(cornerRadius: theme.radii.md, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
        .frame(maxWidth: 420)
    }

    private var tint: Color {
        switch toast.kind {
        case .success: return theme.palette.color(for: .chart5)
        case .info: return theme.palette.color(for: .chart1)
        case .error: return theme.palette.destructive
        }
    }

    private var iconName: String {
        switch toast.kind {
        case .success: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
}
