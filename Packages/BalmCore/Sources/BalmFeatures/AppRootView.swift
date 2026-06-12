import SwiftUI
import BalmDesignSystem

public struct AppRootView: View {
    @Environment(AppEnvironment.self) private var env

    public init() {}

    public var body: some View {
        Group {
            switch env.authState {
            case .loading:
                LoadingView()
            case .signedOut:
                LoginView()
            case .signedIn:
                MainShellView()
            }
        }
        .overlay(alignment: .top) {
            if !env.networkMonitor.isOnline {
                OfflineBanner()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) {
            ToastOverlayView(toaster: env.toaster)
        }
        .animation(.spring(duration: 0.25), value: env.networkMonitor.isOnline)
        .task {
            await env.bootstrap()
        }
    }
}

private struct LoadingView: View {
    @Environment(\.balmTheme) private var theme
    var body: some View {
        ZStack {
            ProgressView()
                .controlSize(.large)
                .tint(theme.palette.primary)
        }
    }
}
