import SwiftUI
import Observation

public struct MainContainerView: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(APIClient.self) private var apiClient
    @Environment(AudioPlayerManager.self) private var audioPlayer
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var selectedTab: Int = 0
    @State private var sidebarSelection: Int? = 0

    public init() {}

    public var body: some View {
        ZStack(alignment: .bottom) {
            if horizontalSizeClass == .regular {
                // iPad / Mac / Regular Width: NavigationSplitView
                NavigationSplitView {
                    sidebarList
                        .navigationTitle("Nexus Music")
                        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
                } detail: {
                    contentForSelectedTab(index: sidebarSelection ?? 0)
                }
            } else {
                // iPhone / Compact Width: 5-Tab TabView
                TabView(selection: $selectedTab) {
                    SyncLibraryTabsView(targetTab: .spotify)
                        .tabItem {
                            Label("Account Sync", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .tag(0)

                    SyncLibraryTabsView(targetTab: .imported)
                        .tabItem {
                            Label("Imported Links", systemImage: "link")
                        }
                        .tag(1)

                    SyncLibraryTabsView(targetTab: .vault)
                        .tabItem {
                            Label("Server Vault", systemImage: "server.rack")
                        }
                        .tag(2)

                    SubsonicPlayerTabView()
                        .tabItem {
                            Label("Music Player", systemImage: "play.circle.fill")
                        }
                        .tag(3)

                    SettingsAndLinksView()
                        .tabItem {
                            Label("Settings", systemImage: "gearshape.fill")
                        }
                        .tag(4)
                }
                .tint(theme.accentEmerald)
            }

            // Floating MiniPlayer Bar Docked Above TabBar
            if audioPlayer.currentTrack != nil {
                MiniPlayerView()
                    .padding(.bottom, horizontalSizeClass == .regular ? 16 : 56)
            }
        }
    }

    // MARK: - Sidebar List for Regular Width

    private var sidebarList: some View {
        List(selection: $sidebarSelection) {
            Section("MY LIBRARY") {
                NavigationLink(value: 0) {
                    Label("Spotify Account", systemImage: "music.note")
                }
                NavigationLink(value: 1) {
                    Label("Imported Links", systemImage: "link")
                }
                NavigationLink(value: 2) {
                    Label("Server Vault", systemImage: "server.rack")
                }
            }

            Section("PLAYER & STREAMING") {
                NavigationLink(value: 3) {
                    Label("Subsonic Player", systemImage: "play.circle.fill")
                }
            }

            Section("ECOSYSTEM") {
                NavigationLink(value: 4) {
                    Label("Settings & Links", systemImage: "gearshape.fill")
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Tab Content Router

    @ViewBuilder
    private func contentForSelectedTab(index: Int) -> some View {
        switch index {
        case 0:
            SyncLibraryTabsView(targetTab: .spotify)
        case 1:
            SyncLibraryTabsView(targetTab: .imported)
        case 2:
            SyncLibraryTabsView(targetTab: .vault)
        case 3:
            SubsonicPlayerTabView()
        case 4:
            SettingsAndLinksView()
        default:
            SyncLibraryTabsView(targetTab: .spotify)
        }
    }
}
