import SwiftUI

struct MainTabView: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            TabView {
                SpotifySyncView()
                    .tabItem {
                        Label("Spotify Sync", systemImage: "arrow.triangle.2.circlepath")
                    }

                ServerLibraryView()
                    .tabItem {
                        Label("Playlists & Vault", systemImage: "music.note.list")
                    }
            }
            .tint(.emerald)

            MiniPlayerView()
        }
    }
}
