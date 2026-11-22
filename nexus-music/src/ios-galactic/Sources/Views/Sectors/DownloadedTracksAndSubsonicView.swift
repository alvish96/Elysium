import SwiftUI

// MARK: - Dedicated Downloaded Tracks Archive (/tracks) & Subsonic Player Tab

public struct DownloadedTracksAndSubsonicView: View {
    @Environment(GalacticThemeManager.self) private var theme
    @Environment(APIClient.self) private var api
    @Environment(AudioPlayerManager.self) private var player

    @State private var mode: Int = 0 // 0 = Master Pool (/tracks), 1 = Subsonic Playlists
    @State private var searchQuery: String = ""
    @State private var subsonicPlaylists: [SubsonicPlaylist] = []
    @State private var selectedPlaylistTracks: [SubsonicTrack] = []
    @State private var selectedSubsonicPlaylist: SubsonicPlaylist?

    public init() {}

    private var filteredPoolTracks: [DownloadedTrackFile] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return api.downloadedTracks }
        return api.downloadedTracks.filter {
            $0.title.lowercased().contains(q) ||
            $0.artist.lowercased().contains(q) ||
            $0.filename.lowercased().contains(q)
        }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("[ MASTER AUDIO POOL // 320KBPS MP3 VAULT ]")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(theme.accent)
                    Spacer()
                    Text("\(api.downloadedTracks.count) TRACKS • \(String(format: "%.1f", api.totalTracksDiskMB)) MB")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(theme.fgMuted)
                }

                Text("DOWNLOADED\nTRACKS.")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(theme.fgPrimary)
                    .lineSpacing(-6)

                // Mode Switcher: Master Pool vs Navidrome Subsonic Playlists
                HStack(spacing: 10) {
                    Button {
                        mode = 0
                    } label: {
                        Text("🎵 MASTER TRACKS (\(api.downloadedTracks.count))")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(mode == 0 ? theme.accent : Color.clear)
                            .foregroundStyle(mode == 0 ? .black : theme.fgMuted)
                            .overlay(ChamferedRectangle(cut: 7).stroke(theme.hairline, lineWidth: 1))
                            .clipShape(ChamferedRectangle(cut: 7))
                    }

                    Button {
                        mode = 1
                        Task { subsonicPlaylists = await api.fetchSubsonicPlaylists() }
                    } label: {
                        Text("🎧 SUBSONIC PLAYLISTS")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(mode == 1 ? theme.accent : Color.clear)
                            .foregroundStyle(mode == 1 ? .black : theme.fgMuted)
                            .overlay(ChamferedRectangle(cut: 7).stroke(theme.hairline, lineWidth: 1))
                            .clipShape(ChamferedRectangle(cut: 7))
                    }
                    Spacer()
                }

                if mode == 0 {
                    // Search Input
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(theme.accent)
                        TextField("SEARCH TITLE, ARTIST, OR FILENAME...", text: $searchQuery)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(theme.fgPrimary)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    .padding(.vertical, 8)
                    .overlay(alignment: .bottom) { Rectangle().fill(theme.hairline).frame(height: 1) }

                    LazyVStack(spacing: 10) {
                        ForEach(Array(filteredPoolTracks.enumerated()), id: \.element.id) { idx, file in
                            HStack(spacing: 12) {
                                Text(String(format: "%02d", idx + 1))
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(theme.accent)
                                    .frame(width: 26, alignment: .leading)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(file.title)
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(theme.fgPrimary)
                                        .lineLimit(1)
                                    Text("👤 \(file.artist) • \(String(format: "%.1f", file.size_mb)) MB")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(theme.fgMuted)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                // Offline Flight Mode Cache Button
                                Button {
                                    if let url = api.directDownloadedTrackStreamURL(filename: file.filename) {
                                        let track = SubsonicTrack(id: file.filename, title: file.title, artist: file.artist, album: nil, duration: nil, coverArt: nil, suffix: "mp3", directStreamURL: url)
                                        Task { await player.cacheTrackForOffline(track) }
                                    }
                                } label: {
                                    Image(systemName: player.isTrackCached(file.filename) ? "checkmark.icloud.fill" : "arrow.down.circle")
                                        .foregroundStyle(player.isTrackCached(file.filename) ? theme.accent : theme.fgMuted)
                                }

                                // Play in Native Audio Player
                                Button {
                                    player.playDownloadedFile(file)
                                } label: {
                                    Text("▶ PLAY")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .foregroundStyle(theme.accent)
                                        .overlay(ChamferedRectangle(cut: 5).stroke(theme.accent, lineWidth: 1))
                                }
                            }
                            .padding(14)
                            .background(theme.bgElevated)
                            .overlay(ChamferedRectangle(cut: 10).stroke(theme.hairline, lineWidth: 1))
                            .clipShape(ChamferedRectangle(cut: 10))
                        }
                    }
                } else {
                    // Subsonic Playlists Browser
                    if let selected = selectedSubsonicPlaylist {
                        HStack {
                            Button("← ALL PLAYLISTS") {
                                selectedSubsonicPlaylist = nil
                            }
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(theme.accent)

                            Spacer()

                            Button("▶ PLAY ALL") {
                                player.playPlaylist(tracks: selectedPlaylistTracks, startingAt: 0)
                            }
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(theme.accent)
                            .foregroundStyle(.black)
                        }

                        Text(selected.name.uppercased())
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(theme.fgPrimary)

                        ForEach(Array(selectedPlaylistTracks.enumerated()), id: \.element.id) { idx, trk in
                            Button {
                                player.playPlaylist(tracks: selectedPlaylistTracks, startingAt: idx)
                            } label: {
                                HStack {
                                    Text(String(format: "%02d", idx + 1))
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundStyle(theme.accent)
                                    VStack(alignment: .leading) {
                                        Text(trk.title)
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundStyle(theme.fgPrimary)
                                        Text(trk.artist ?? "Unknown")
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(theme.fgMuted)
                                    }
                                    Spacer()
                                    Image(systemName: "play.fill")
                                        .foregroundStyle(theme.accent)
                                }
                                .padding(12)
                                .background(theme.bgElevated)
                                .overlay(Rectangle().stroke(theme.hairline, lineWidth: 1))
                            }
                        }
                    } else {
                        ForEach(subsonicPlaylists) { pl in
                            Button {
                                selectedSubsonicPlaylist = pl
                                Task {
                                    selectedPlaylistTracks = await api.fetchSubsonicPlaylistTracks(playlistId: pl.id)
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(pl.name)
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundStyle(theme.fgPrimary)
                                        Text("\(pl.songCount ?? 0) SONGS • OWNER: \((pl.owner ?? "alvish").uppercased())")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(theme.accent)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(theme.accent)
                                }
                                .padding(16)
                                .background(theme.bgElevated)
                                .overlay(ChamferedRectangle(cut: 10).stroke(theme.hairline, lineWidth: 1))
                                .clipShape(ChamferedRectangle(cut: 10))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 110)
        }
        .refreshable {
            await api.fetchDownloadedTracksArchive()
        }
    }
}
