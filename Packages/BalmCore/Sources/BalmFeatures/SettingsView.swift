import SwiftUI
import BalmDesignSystem

#if canImport(AppKit)
import AppKit
#endif

public struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.balmTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var showingProjectChooser = false

    #if canImport(AppKit)
    @State private var hostWindow: NSWindow?
    #endif

    public init() {}

    public var body: some View {
        container
            .sheet(isPresented: $showingProjectChooser) {
                ProjectChooserView(isFirstRun: false)
                    .environment(env)
                    .themed()
            }
            .onChange(of: env.authState) { _, newState in
                if case .signedOut = newState { closeOnSignOut() }
            }
    }

    // MARK: - Platform containers

    @ViewBuilder
    private var container: some View {
        #if os(macOS)
        TabView {
            Form { projectSection; notificationsSection }.formStyle(.grouped)
                .tabItem { Label("General", systemImage: "gearshape") }
            Form { siteSection; networkSection; signOutSection }.formStyle(.grouped)
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
            Form { aboutSection }.formStyle(.grouped)
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 540, height: 440)
        .background(WindowAccessor { window in
            if hostWindow == nil { hostWindow = window }
        })
        #else
        NavigationStack {
            Form {
                projectSection
                notificationsSection
                siteSection
                networkSection
                signOutSection
                aboutSection
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #endif
    }

    private func closeOnSignOut() {
        #if canImport(AppKit)
        (hostWindow ?? NSApp.keyWindow)?.performClose(nil)
        #else
        dismiss()
        #endif
    }

    // MARK: - Sections

    @ViewBuilder
    private var projectSection: some View {
        Section("Project") {
            if let project = env.activeProjectStore.project {
                LabeledContent("Name", value: project.name)
                LabeledContent("Key", value: project.key)
            } else {
                Text("No project selected.").foregroundStyle(.secondary)
            }
            Button("Change Project…") { showingProjectChooser = true }
        }
    }

    @ViewBuilder
    private var notificationsSection: some View {
        Section {
            Toggle("System notifications", isOn: systemNotificationsBinding)
            Picker("Check every", selection: pollIntervalBinding) {
                ForEach(InboxStore.allowedPollIntervals, id: \.self) { seconds in
                    Text(pollIntervalLabel(seconds)).tag(seconds)
                }
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text(notificationsFooterText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var notificationsFooterText: String {
        var text = "Notifications are synthesized by periodically polling Jira — they cover issues "
            + "you're assigned, reported, or watching (mentions only within those issues)."
        if env.inboxStore.readSyncUnavailable {
            text += "\n\nRead state isn't syncing across devices — sign out and back in to grant the new permission."
        }
        return text
    }

    private var systemNotificationsBinding: Binding<Bool> {
        Binding(
            get: { env.inboxStore.systemNotificationsEnabled },
            set: { env.inboxStore.systemNotificationsEnabled = $0 }
        )
    }

    private var pollIntervalBinding: Binding<Int> {
        Binding(
            get: { env.inboxStore.pollIntervalSeconds },
            set: { env.inboxStore.pollIntervalSeconds = $0 }
        )
    }

    private func pollIntervalLabel(_ seconds: Int) -> String {
        let minutes = seconds / 60
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }

    @ViewBuilder
    private var siteSection: some View {
        Section("Site") {
            if case .signedIn(let siteName, let siteURL, let user) = env.authState {
                LabeledContent("Name", value: siteName)
                LabeledContent("URL", value: siteURL.absoluteString)
                if let user {
                    LabeledContent("Signed in as", value: user.displayName)
                    if let email = user.emailAddress {
                        LabeledContent("Email", value: email)
                    }
                }
            } else {
                Text("Not signed in.").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var networkSection: some View {
        Section("Network") {
            HStack {
                Image(systemName: env.networkMonitor.isOnline ? "wifi" : "wifi.slash")
                    .foregroundStyle(env.networkMonitor.isOnline ? .green : .red)
                Text(env.networkMonitor.isOnline ? "Online" : "Offline")
                Spacer()
                if env.networkMonitor.isExpensive {
                    Text("Expensive connection")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var signOutSection: some View {
        Section {
            Button("Sign Out", role: .destructive) {
                Task { await env.signOut() }
            }
        } footer: {
            Text("Signing out clears your Atlassian tokens and the cached project.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: Self.versionString)
            LabeledContent("Build", value: Self.buildString)
        }
    }

    private static var versionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private static var buildString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
}

#if canImport(AppKit)
/// Bridges the hosting `NSWindow` out of SwiftUI so callers can drive
/// AppKit-level actions (like `performClose`) on the exact window they're in.
private struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onResolve(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onResolve(nsView.window) }
    }
}
#endif
