import SwiftUI
import Observation

// MARK: - Subsonic Player Tab View

public struct SubsonicPlayerTabView: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(APIClient.self) private var apiClient
    @Environment(AudioPlayerManager.self) private var audioPlayer

    @State private var playlists: [SubsonicPlaylist] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var filterQuery: String = ""

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                AppCanvasBackgroundView()

                VStack(spacing: 0) {
                    // Search & Stats Bar
                    HStack(spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.caption)
                                .foregroundStyle(theme.mutedText)

                            TextField("Filter Subsonic playlists...", text: $filterQuery)
                                .font(.subheadline)
                                .foregroundStyle(theme.primaryText)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)

                            if !filterQuery.isEmpty {
                                Button {
                                    filterQuery = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(theme.mutedText)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(theme.inputBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(theme.cardBorder, lineWidth: 1.0)
                        )

                        Button {
                            Task { await loadPlaylists() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption.weight(.bold))
                                .padding(10)
                                .background(theme.pillBackground)
                                .foregroundStyle(theme.primaryText)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(theme.cardBorder, lineWidth: 0.8)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                    // Error Notification
                    if let error = errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color(hex: "#F43F5E"))
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(Color(hex: "#F43F5E"))
                            Spacer()
                            Button("Retry") {
                                Task { await loadPlaylists() }
                            }
                            .font(.caption.weight(.bold))
                            .foregroundStyle(theme.accentEmerald)
                        }
                        .padding(10)
                        .background(Color(hex: "#F43F5E").opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    }

                    // Content State
                    if isLoading && playlists.isEmpty {
                        VStack(spacing: 12) {
                            Spacer()
                            ProgressView()
                                .tint(theme.accentEmerald)
                                .scaleEffect(1.2)
                            Text("Querying Navidrome Library...")
                                .font(.subheadline)
                                .foregroundStyle(theme.secondaryText)
                            Spacer()
                        }
                    } else if filteredPlaylists.isEmpty {
                        VStack(spacing: 12) {
                            Spacer()
                            Image(systemName: "music.note.list")
                                .font(.system(size: 48))
                                .foregroundStyle(theme.mutedText)
                            Text("No Subsonic Playlists Found")
                                .font(.headline)
                                .foregroundStyle(theme.primaryText)
                            Text("Playlists synced from Spotify or imported via URL will appear here once indexed by Navidrome.")
                                .font(.footnote)
                                .foregroundStyle(theme.secondaryText)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                            Spacer()
                        }
                    } else {
                        ScrollView {
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 310, maximum: 500), spacing: 12)],
                                spacing: 12
                            ) {
                                ForEach(filteredPlaylists) { playlist in
                                    NavigationLink(destination: SubsonicPlaylistDetailView(playlist: playlist)) {
                                        playlistCard(playlist)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 80) // Spacing for MiniPlayer
                        }
                        .refreshable {
                            await loadPlaylists()
                        }
                    }
                }
            }
            .navigationTitle("Music Player")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await loadPlaylists()
            }
        }
    }

    private var filteredPlaylists: [SubsonicPlaylist] {
        let q = filterQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return playlists }
        return playlists.filter {
            $0.name.lowercased().contains(q) ||
            ($0.owner?.lowercased().contains(q) == true)
        }
    }

    private func playlistCard(_ playlist: SubsonicPlaylist) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: apiClient.getCoverArtURL(coverId: playlist.coverArt)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure, .empty:
                    ZStack {
                        Rectangle().fill(theme.cardBorder.opacity(0.3))
                        Image(systemName: "music.note.list")
                            .font(.title3)
                            .foregroundStyle(theme.mutedText)
                    }
                @unknown default:
                    Rectangle().fill(theme.cardBorder.opacity(0.3))
                }
            }
            .frame(width: 58, height: 58)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(theme.cardBorder, lineWidth: 0.8)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let owner = playlist.owner, !owner.isEmpty {
                        Text("👤 \(owner)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(theme.secondaryText)
                    }

                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(theme.mutedText)

                    Text("\(playlist.songCount ?? 0) tracks")
                        .font(.caption2.monospaced())
                        .foregroundStyle(theme.accentEmerald)

                    if let dur = playlist.duration, dur > 0 {
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(theme.mutedText)
                        Text(formatDuration(seconds: dur))
                            .font(.caption2.monospaced())
                            .foregroundStyle(theme.mutedText)
                    }
                }

                HStack(spacing: 4) {
                    Image(systemName: playlist.public == true ? "globe" : "lock.fill")
                        .font(.system(size: 9))
                    Text(playlist.public == true ? "Public Community" : "Private Vault")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(playlist.public == true ? theme.accentEmerald : theme.mutedText)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(playlist.public == true ? theme.accentEmeraldGlow : theme.pillBackground)
                .clipShape(Capsule())
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(theme.mutedText)
        }
        .padding(12)
        .glassCard(cornerRadius: 14, padding: nil)
    }

    private func loadPlaylists() async {
        isLoading = true
        errorMessage = nil
        do {
            let result = try await apiClient.fetchSubsonicPlaylists()
            await MainActor.run {
                self.playlists = result
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Navidrome connection error: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }

    private func formatDuration(seconds: Int) -> String {
        let mins = seconds / 60
        let hours = mins / 60
        if hours > 0 {
            return "\(hours)h \(mins % 60)m"
        } else {
            return "\(mins)m"
        }
    }
}

// MARK: - Subsonic Playlist Detail View

public struct SubsonicPlaylistDetailView: View {
    public let playlist: SubsonicPlaylist

    @Environment(ThemeManager.self) private var theme
    @Environment(APIClient.self) private var apiClient
    @Environment(AudioPlayerManager.self) private var audioPlayer

    @State private var tracks: [SubsonicTrack] = []
    @State private var isLoading: Bool = false
    @State private var isDownloadingAll: Bool = false
    @State private var downloadProgressText: String = ""
    @State private var errorMessage: String? = nil

    public init(playlist: SubsonicPlaylist) {
        self.playlist = playlist
    }

    public var body: some View {
        ZStack {
            AppCanvasBackgroundView()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 16) {
                        // Header Hero Section
                        playlistHeroHeader

                        // Play / Shuffle / Offline Action Bar
                        actionControlsBar

                        // Track List
                        if isLoading && tracks.isEmpty {
                            VStack(spacing: 10) {
                                ProgressView()
                                    .tint(theme.accentEmerald)
                                Text("Loading tracks...")
                                    .font(.caption)
                                    .foregroundStyle(theme.secondaryText)
                            }
                            .padding(.top, 40)
                        } else if tracks.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "music.note")
                                    .font(.largeTitle)
                                    .foregroundStyle(theme.mutedText)
                                Text("No tracks in playlist.")
                                    .font(.subheadline)
                                    .foregroundStyle(theme.secondaryText)
                            }
                            .padding(.top, 40)
                        } else {
                            LazyVStack(spacing: 6) {
                                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                                    trackRowView(track: track, index: index)
                                }
                            }
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 80) // Clearance for floating MiniPlayer
                }
            }
        }
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadTracks()
        }
    }

    // MARK: - Hero Header

    private var playlistHeroHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            AsyncImage(url: apiClient.getCoverArtURL(coverId: playlist.coverArt)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure, .empty:
                    ZStack {
                        Rectangle().fill(theme.cardBorder.opacity(0.3))
                        Image(systemName: "music.note.list")
                            .font(.largeTitle)
                            .foregroundStyle(theme.mutedText)
                    }
                @unknown default:
                    Rectangle().fill(theme.cardBorder.opacity(0.3))
                }
            }
            .frame(width: 108, height: 108)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.black.opacity(0.35), radius: 10, y: 5)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(theme.cardBorder, lineWidth: 1.0)
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(playlist.name)
                    .font(.title3.weight(.black))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(2)

                if let owner = playlist.owner, !owner.isEmpty {
                    Text("Curated by \(owner)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(theme.secondaryText)
                }

                HStack(spacing: 8) {
                    Text("\(tracks.count) tracks")
                        .font(.caption.monospaced())
                        .foregroundStyle(theme.accentEmerald)

                    if let dur = playlist.duration, dur > 0 {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(theme.mutedText)
                        Text(formatDuration(seconds: dur))
                            .font(.caption.monospaced())
                            .foregroundStyle(theme.mutedText)
                    }
                }

                HStack(spacing: 4) {
                    Image(systemName: playlist.public == true ? "globe" : "lock.fill")
                        .font(.system(size: 9))
                    Text(playlist.public == true ? "Public Community" : "Private Vault")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(playlist.public == true ? theme.accentEmerald : theme.mutedText)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(playlist.public == true ? theme.accentEmeraldGlow : theme.pillBackground)
                .clipShape(Capsule())
            }

            Spacer()
        }
        .padding(14)
        .glassCard(cornerRadius: 18, padding: nil)
    }

    // MARK: - Action Controls Bar

    private var actionControlsBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                // Play All Button
                Button {
                    audioPlayer.isShuffleEnabled = false
                    audioPlayer.playPlaylist(tracks: tracks, startingAt: 0)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.caption.weight(.bold))
                        Text("Play All")
                            .font(.caption.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(theme.accentEmerald)
                    .foregroundStyle(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: theme.accentEmerald.opacity(0.3), radius: 6, y: 2)
                }
                .buttonStyle(.plain)
                .disabled(tracks.isEmpty)

                // Shuffle Button
                Button {
                    audioPlayer.isShuffleEnabled = true
                    audioPlayer.playPlaylist(tracks: tracks, startingAt: 0)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "shuffle")
                            .font(.caption.weight(.bold))
                        Text("Shuffle")
                            .font(.caption.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(theme.pillBackground)
                    .foregroundStyle(theme.primaryText)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(theme.cardBorder, lineWidth: 1.0)
                    )
                }
                .buttonStyle(.plain)
                .disabled(tracks.isEmpty)
            }

            // Download for Offline Flight Mode
            Button {
                triggerOfflineDownload()
            } label: {
                HStack(spacing: 6) {
                    if isDownloadingAll {
                        ProgressView()
                            .tint(theme.accentEmerald)
                            .scaleEffect(0.8)
                        Text(downloadProgressText.isEmpty ? "Caching Tracks..." : downloadProgressText)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(theme.accentEmerald)
                    } else {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.caption)
                        Text("Download Playlist for Offline Flight Mode")
                            .font(.caption.weight(.bold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(theme.inputBackground)
                .foregroundStyle(theme.accentEmerald)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(theme.accentEmerald.opacity(0.35), lineWidth: 0.8)
                )
            }
            .buttonStyle(.plain)
            .disabled(isDownloadingAll || tracks.isEmpty)
        }
    }

    // MARK: - Track Row View

    private func trackRowView(track: SubsonicTrack, index: Int) -> some View {
        let isCurrent = (audioPlayer.currentTrack?.id == track.id)
        let isCached = audioPlayer.isTrackCached(track.id)

        return HStack(spacing: 12) {
            // Track Number or Equalizer
            ZStack {
                if isCurrent && audioPlayer.isPlaying {
                    Image(systemName: "waveform")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(theme.accentEmerald)
                } else {
                    Text("\(index + 1)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(isCurrent ? theme.accentEmerald : theme.mutedText)
                }
            }
            .frame(width: 22, alignment: .center)

            // Track Meta
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.subheadline.weight(isCurrent ? .bold : .medium))
                    .foregroundStyle(isCurrent ? theme.accentEmerald : theme.primaryText)
                    .lineLimit(1)

                Text(track.artist ?? "Unknown Artist")
                    .font(.caption2)
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            // Offline Caching Indicator
            if isCached {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(theme.accentEmerald)
            }

            // Duration
            if let dur = track.duration {
                Text(formatSeconds(dur))
                    .font(.caption2.monospaced())
                    .foregroundStyle(theme.mutedText)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isCurrent ? theme.accentEmeraldGlow : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture {
            audioPlayer.playPlaylist(tracks: tracks, startingAt: index)
        }
    }

    // MARK: - Actions

    private func loadTracks() async {
        isLoading = true
        errorMessage = nil
        do {
            let res = try await apiClient.fetchSubsonicPlaylistTracks(playlistId: playlist.id)
            await MainActor.run {
                self.tracks = res
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load tracks: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }

    private func triggerOfflineDownload() {
        guard !tracks.isEmpty else { return }
        isDownloadingAll = true

        Task {
            for (idx, track) in tracks.enumerated() {
                await MainActor.run {
                    self.downloadProgressText = "Caching \(idx + 1) of \(tracks.count)..."
                }
                if !audioPlayer.isTrackCached(track.id) {
                    try? await audioPlayer.downloadTrackForOffline(track)
                }
            }
            await MainActor.run {
                self.isDownloadingAll = false
                self.downloadProgressText = ""
            }
        }
    }

    private func formatSeconds(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func formatDuration(seconds: Int) -> String {
        let mins = seconds / 60
        let hours = mins / 60
        if hours > 0 {
            return "\(hours)h \(mins % 60)m"
        } else {
            return "\(mins)m"
        }
    }
}
