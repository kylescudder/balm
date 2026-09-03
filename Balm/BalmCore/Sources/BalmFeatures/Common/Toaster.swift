import SwiftUI
import Observation
import BalmModels
import BalmAPI
import BalmDesignSystem

@MainActor
@Observable
public final class Toaster {
    public struct ToastAction: Identifiable, Sendable {
        public let id = UUID()
        public let title: String
        public let handler: @MainActor () -> Void
        public init(title: String, handler: @escaping @MainActor () -> Void) {
            self.title = title
            self.handler = handler
        }
    }

    public struct Toast: Identifiable, Sendable, Equatable {
        public let id = UUID()
        public let message: String
        public let kind: Kind
        public let actions: [ToastAction]
        public init(message: String, kind: Kind, actions: [ToastAction] = []) {
            self.message = message
            self.kind = kind
            self.actions = actions
        }
        public enum Kind: Sendable, Equatable { case success, info, error }
        public static func == (lhs: Toast, rhs: Toast) -> Bool { lhs.id == rhs.id }
    }

    public private(set) var toasts: [Toast] = []
    private let defaultDuration: TimeInterval
    /// Toasts carrying actions linger longer so there's time to click one.
    private let actionDuration: TimeInterval = 6.0

    public init(defaultDuration: TimeInterval = 2.5) {
        self.defaultDuration = defaultDuration
    }

    public func info(_ message: String) { show(message, kind: .info) }
    public func success(_ message: String, actions: [ToastAction] = []) {
        show(message, kind: .success, actions: actions)
    }
    public func error(_ message: String) { show(message, kind: .error, duration: 4.0) }

    /// Reports a failure as "<context>: <description>", except for a cancelled
    /// request, which the user caused and does not need to hear about.
    public func report(_ error: Error, _ context: String) {
        guard !error.isCancellation else { return }
        self.error("\(context): \(error.localizedDescription)")
    }

    public func show(
        _ message: String,
        kind: Toast.Kind,
        duration: TimeInterval? = nil,
        actions: [ToastAction] = []
    ) {
        let toast = Toast(message: message, kind: kind, actions: actions)
        toasts.append(toast)
        switch kind {
        case .success: Haptics.fire(.success)
        case .error: Haptics.fire(.error)
        case .info: break
        }
        let life = duration ?? (actions.isEmpty ? defaultDuration : actionDuration)
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
    let toaster: Toaster

    var body: some View {
        VStack(spacing: 8) {
            ForEach(toaster.toasts) { toast in
                ToastBubble(toast: toast, dismiss: { toaster.dismiss(toast.id) })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onTapGesture { toaster.dismiss(toast.id) }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(!toaster.toasts.isEmpty)
        .animation(.spring(duration: 0.25), value: toaster.toasts.map(\.id))
    }
}

/// System material, hairline edge, the done glyph as the success mark.
private struct ToastBubble: View {
    @Environment(\.balmTheme) private var theme
    let toast: Toaster.Toast
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            icon
            Text(toast.message)
                .font(.body)
                .lineLimit(2)
            Spacer(minLength: 4)
            ForEach(toast.actions) { action in
                Button(action.title) {
                    action.handler()
                    dismiss()
                }
                .buttonStyle(.borderless)
                .font(.callout.weight(.semibold))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .frame(maxWidth: 440)
    }

    @ViewBuilder
    private var icon: some View {
        switch toast.kind {
        case .success:
            StatusGlyph(spec: StatusHealth.done.representativeGlyph, size: 16)
        case .info:
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }
}
