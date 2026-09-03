import SwiftUI
import BalmAuth
import BalmDesignSystem

/// The mark, the wordmark, one line, one button.
public struct LoginView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.balmTheme) private var theme

    @State private var isSigningIn = false

    public init() {}

    public var body: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 14) {
                Image("BalmMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
                    .accessibilityHidden(true)
                Text("Balm.")
                    .font(theme.typography.wordmark)
                Text("Jira, with room to think.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if env.oauthConfig.clientID.isEmpty {
                configurationMissingMessage
            } else {
                Button(action: signIn) {
                    HStack(spacing: 8) {
                        if isSigningIn { ProgressView().controlSize(.small) }
                        Text(isSigningIn ? "Signing in" : "Sign in with Atlassian")
                    }
                    .frame(minWidth: 220)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(isSigningIn)
            }

            if let err = env.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer()
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func signIn() {
        Task {
            isSigningIn = true
            let anchor = ASPresentationAnchorBridge.resolveFromActiveScene()
            await env.signIn(anchor: anchor)
            isSigningIn = false
        }
    }

    @ViewBuilder
    private var configurationMissingMessage: some View {
        ContentUnavailableView {
            Label("Atlassian client ID is not configured", systemImage: "key")
        } description: {
            Text("Add ATLASSIAN_CLIENT_ID to Config/Secrets.xcconfig, then rebuild.")
        }
        .frame(maxHeight: 200)
    }
}
