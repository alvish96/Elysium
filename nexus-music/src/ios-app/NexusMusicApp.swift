import SwiftUI
import Observation

@main
public struct NexusMusicApp: App {
    @State private var apiClient = APIClient.shared
    @State private var wsManager = WebSocketManager.shared
    @State private var audioPlayer = AudioPlayerManager.shared
    @State private var theme = ThemeManager.shared

    public init() {}

    public var body: some Scene {
        WindowGroup {
            Group {
                if apiClient.isAuthenticated {
                    MainContainerView()
                } else {
                    LoginView()
                }
            }
            .environment(apiClient)
            .environment(wsManager)
            .environment(audioPlayer)
            .environment(theme)
            .preferredColorScheme(theme.isLightMode ? .light : .dark)
            .task {
                apiClient.checkExistingLogin()
            }
        }
    }
}
