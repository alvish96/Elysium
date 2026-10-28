import SwiftUI

struct ServerLibraryView: View {
    @Environment(APIClient.self) private var apiClient
    @Environment(AudioPlayerManager.self) private var audioPlayer

    @State private var playlists: [SubsonicPlaylist] = []
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.06, green: 0.09, blue: 0.16).ignoresSafeArea()

                List {
                    ForEach(playlists) { playlist in
                        NavigationLink(destination: PlaylistDetailView(playlist: playlist)) {
                            HStack(spacing: 14) {
                                AsyncImage(url: apiClient.getCoverArtURL(coverId: playlist.coverArt)) { img in
                                    img.resizable().aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Rectangle().fill(Color.gray.opacity(0.3))
                                }
                                .frame(width: 50, height: 50)
                                .clipShape(RoundedRectangle(cornerRadius: 10))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(playlist.name)
                                        .font(.headline)
                                        .foregroundStyle(.white)

                                    Text("\(playlist.songCount) Songs • \(playlist.public == true ? "🌍 Public" : "🔒 Private")")
                                        .font(.caption)
                                        .foregroundStyle(.gray)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(Color(red: 0.1, green: 0.14, blue: 0.22))
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Library & Vault")
            .task {
                loadSubsonicPlaylists()
            }
        }
    }

    private func loadSubsonicPlaylists() {
        isLoading = true
        Task {
            if let list = try? await apiClient.fetchSubsonicPlaylists() {
                playlists = list
            }
            isLoading = false
        }
    }
}

struct PlaylistDetailView: View {
    let playlist: SubsonicPlaylist
    @Environment(APIClient.self) private var apiClient
    @Environment(AudioPlayerManager.self) private var audioPlayer

    @State private var tracks: [SubsonicTrack] = []
    @State private var isDownloadingAll = false

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.09, blue: 0.16).ignoresSafeArea()

            List {
                Section {
                    Button {
                        Task {
                            isDownloadingAll = true
                            for track in tracks {
                                try? await audioPlayer.downloadForOffline(track: track)
                            }
                            isDownloadingAll = false
                        }
                    } label: {
                        HStack {
                            Image(systemName: isDownloadingAll ? "arrow.down.circle.fill" : "arrow.down.circle")
                            Text(isDownloadingAll ? "Caching Playlist..." : "Download for Offline Flight Mode")
                        }
                        .foregroundStyle(Color.emerald)
                    }
                }
                .listRowBackground(Color(red: 0.1, green: 0.14, blue: 0.22))

                Section("Tracks") {
                    ForEach(tracks) { track in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(track.title)
                                    .font(.body)
                                    .foregroundStyle(.white)
                                Text(track.artist ?? "Unknown")
                                    .font(.caption)
                                    .foregroundStyle(.gray)
                            }

                            Spacer()

                            if audioPlayer.isTrackCached(trackId: track.id) {
                                Image(systemName: "arrow.down.circle.fill")
                                    .foregroundStyle(Color.emerald)
                                    .font(.caption)
                            }

                            Button {
                                audioPlayer.playTrack(track)
                            } label: {
                                Image(systemName: "play.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(Color.emerald)
                            }
                        }
                        .listRowBackground(Color(red: 0.1, green: 0.14, blue: 0.22))
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(playlist.name)
        .task {
            if let detail = try? await apiClient.fetchSubsonicPlaylistDetail(playlistId: playlist.id) {
                tracks = detail
            }
        }
    }
}
