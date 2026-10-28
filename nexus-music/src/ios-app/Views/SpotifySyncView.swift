import SwiftUI
import AuthenticationServices

struct SpotifySyncView: View {
    @Environment(APIClient.self) private var apiClient
    @Environment(WebSocketManager.self) private var wsManager

    @State private var playlists: [SpotifyPlaylist] = []
    @State private var isConnectedSpotify = false
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.06, green: 0.09, blue: 0.16).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // Spotify Status Header
                        spotifyStatusBar

                        // Playlists Grid / List
                        if isLoading {
                            ProgressView("Fetching Spotify Playlists...").tint(.emerald)
                                .padding(.top, 40)
                        } else {
                            ForEach($playlists) { $playlist in
                                playlistCard(for: $playlist)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Spotify Sync")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await loadPlaylists() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task {
                await loadPlaylists()
            }
            .onChange(of: wsManager.lastEvent?.downloaded_count) { _, _ in
                handleWebSocketUpdate()
            }
        }
    }

    private var spotifyStatusBar: some View {
        HStack {
            Image(systemName: "waveform.circle.fill")
                .font(.title2)
                .foregroundStyle(isConnectedSpotify ? Color.emerald : .yellow)

            VStack(alignment: .leading, spacing: 2) {
                Text(isConnectedSpotify ? "Spotify Connected" : "Spotify Not Connected")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Text("Background worker syncs every 2 hours")
                    .font(.caption2)
                    .foregroundStyle(.gray)
            }

            Spacer()

            if !isConnectedSpotify {
                Button("Connect") {
                    startSpotifyOAuth()
                }
                .font(.caption.bold())
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.emerald)
                .foregroundStyle(.black)
                .clipShape(Capsule())
            }
        }
        .padding()
        .background(Color(red: 0.1, green: 0.14, blue: 0.22))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func playlistCard(for playlist: Binding<SpotifyPlaylist>) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                AsyncImage(url: URL(string: playlist.wrappedValue.cover_url ?? "")) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(Color.gray.opacity(0.3))
                }
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text(playlist.wrappedValue.name)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text("\(playlist.wrappedValue.total_tracks) tracks • \(playlist.wrappedValue.folder_slug)")
                        .font(.caption)
                        .foregroundStyle(.gray)
                }

                Spacer()

                // Bolt trigger
                Button {
                    Task {
                        try? await apiClient.triggerSyncNow(spotifyId: playlist.wrappedValue.id)
                    }
                } label: {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(playlist.wrappedValue.is_synced ? Color.yellow : .gray.opacity(0.4))
                }
                .disabled(!playlist.wrappedValue.is_synced)
            }

            // Progress Bar
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: playlist.wrappedValue.progressFraction)
                    .tint(.emerald)

                HStack {
                    Text(playlist.wrappedValue.sync_status.capitalized)
                        .font(.caption2)
                        .foregroundStyle(playlist.wrappedValue.sync_status == "syncing" ? .yellow : .gray)

                    Spacer()

                    Text("\(playlist.wrappedValue.downloaded_tracks)/\(playlist.wrappedValue.total_tracks)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.gray)
                }
            }

            Divider().background(Color.gray.opacity(0.2))

            // Toggles
            HStack {
                Toggle("Sync", isOn: Binding(
                    get: { playlist.wrappedValue.is_synced },
                    set: { val in
                        playlist.wrappedValue.is_synced = val
                        updatePlaylistConfig(playlist.wrappedValue)
                    }
                ))
                .toggleStyle(SwitchToggleStyle(tint: .emerald))
                .labelsHidden()

                Text("Sync")
                    .font(.caption.bold())
                    .foregroundStyle(playlist.wrappedValue.is_synced ? .white : .gray)

                Spacer()

                // Private vs Public Picker
                Picker("Visibility", selection: Binding(
                    get: { playlist.wrappedValue.visibility },
                    set: { val in
                        playlist.wrappedValue.visibility = val
                        updatePlaylistConfig(playlist.wrappedValue)
                    }
                )) {
                    Text("🔒 Private").tag("private")
                    Text("🌍 Public").tag("public")
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
            }
        }
        .padding()
        .background(Color(red: 0.1, green: 0.14, blue: 0.22))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func loadPlaylists() async {
        isLoading = true
        if let status = try? await apiClient.fetchSpotifyStatus() {
            isConnectedSpotify = status.connected
        }
        if let list = try? await apiClient.fetchSpotifyPlaylists() {
            playlists = list
        }
        isLoading = false
    }

    private func updatePlaylistConfig(_ p: SpotifyPlaylist) {
        Task {
            try? await apiClient.configurePlaylist(
                spotifyId: p.id,
                isSynced: p.is_synced,
                visibility: p.visibility,
                folderSlug: p.folder_slug
            )
        }
    }

    private func handleWebSocketUpdate() {
        guard let event = wsManager.lastEvent, let pid = event.playlist_id else { return }
        if let idx = playlists.firstIndex(where: { $0.id == pid }) {
            if let downloaded = event.downloaded_count {
                playlists[idx].downloaded_tracks = downloaded
            }
            if let total = event.total {
                playlists[idx].total_tracks = total
            }
            if event.event == "SYNC_COMPLETED" {
                playlists[idx].sync_status = "completed"
            } else if event.event == "TRACK_PROGRESS" {
                playlists[idx].sync_status = "syncing"
            }
        }
    }

    private func startSpotifyOAuth() {
        guard let authURL = URL(string: "\(apiClient.syncBaseURL)/api/v1/spotify/login") else { return }
        let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: "nexusmusic") { callbackURL, error in
            Task { await loadPlaylists() }
        }
        session.presentationContextProvider = KeyWindowPresentationContextProvider.shared
        session.start()
    }
}

final class KeyWindowPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = KeyWindowPresentationContextProvider()
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
