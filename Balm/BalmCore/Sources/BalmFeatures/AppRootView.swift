import SwiftUI
import BalmAuth
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
        // Posted by TokenStore when the rotating refresh token is rejected
        // outright: the session can never recover, so land on the login
        // screen instead of stranding the user on raw HTTP errors.
        .onReceive(NotificationCenter.default.publisher(for: .balmSessionExpired)) { _ in
            guard case .signedIn = env.authState else { return }
            env.toaster.info("Your session has expired — please sign in again")
            Task { await env.signOut() }
        }
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
