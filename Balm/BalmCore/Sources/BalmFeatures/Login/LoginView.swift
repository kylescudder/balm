import SwiftUI
import BalmAuth
import BalmDesignSystem

public struct LoginView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.balmTheme) private var theme

    @State private var isSigningIn = false

    public init() {}

    public var body: some View {
        ZStack {

            VStack(spacing: theme.spacing.xl) {
                Spacer()

                VStack(spacing: theme.spacing.m) {
                    Image("BalmMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 96, height: 96)
                    Text("Balm")
                        .font(theme.typography.largeTitle)
                        .foregroundStyle(theme.palette.foreground)
                    Text("A calmer way to work your issues.")
                        .font(theme.typography.callout)
                        .foregroundStyle(theme.palette.mutedForeground)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                if env.oauthConfig.clientID.isEmpty {
                    configurationMissingMessage
                } else {
                    Button(action: signIn) {
                        HStack(spacing: theme.spacing.s) {
                            if isSigningIn { ProgressView().controlSize(.small) }
                            Text(isSigningIn ? "Signing in…" : "Sign in with Atlassian")
                        }
                        .frame(minWidth: 240)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSigningIn)
                }

                if let err = env.lastError {
                    Text(err)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.palette.destructive)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, theme.spacing.xl)
                }

                Spacer()
            }
            .padding(theme.spacing.xl)
            .frame(maxWidth: 480)
        }
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
        VStack(spacing: theme.spacing.s) {
            Text("Atlassian client ID is not configured.")
                .font(theme.typography.headline)
                .foregroundStyle(theme.palette.destructive)
            Text("Add `ATLASSIAN_CLIENT_ID` to Info.plist before signing in.")
                .font(theme.typography.caption)
                .foregroundStyle(theme.palette.mutedForeground)
                .multilineTextAlignment(.center)
        }
        .padding(theme.spacing.l)
        .background(theme.palette.card)
        .clipShape(RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous))
    }
}
