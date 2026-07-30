import SwiftUI
import BalmAuth
import BalmAPI
import BalmPersistence
import BalmDesignSystem
import BalmFeatures

@main
struct BalmApp: App {
    @State private var appEnvironment = AppEnvironment.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appEnvironment)
                .themed()
        }
        #if os(macOS)
        .commands { BalmCommands() }
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(appEnvironment)
                .themed()
        }
        #endif
    }
}
