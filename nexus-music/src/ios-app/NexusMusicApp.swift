import SwiftUI

@main
struct NexusMusicApp: App {
    @State private var apiClient = APIClient.shared
    @State private var wsManager = WebSocketManager.shared
    @State private var audioPlayer = AudioPlayerManager.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if apiClient.isAuthenticated {
                    MainTabView()
                        .environment(apiClient)
                        .environment(wsManager)
                        .environment(audioPlayer)
                } else {
                    LoginView()
                        .environment(apiClient)
                }
            }
            .preferredColorScheme(.dark)
            .task {
                apiClient.checkExistingLogin()
            }
        }
    }
}
