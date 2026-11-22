import SwiftUI

// MARK: - Sector 03: Holocron Archives (Contained Scrollbox, Check New, Re-Sync All & Spotify/Feishin Links)

public struct HolocronArchivesView: View {
    @Environment(GalacticThemeManager.self) private var theme
    @Environment(APIClient.self) private var api
    @Environment(\.openURL) private var openURL

    @State private var selectedSource: ArchiveSource = .spotify
    @State private var selectedFilter: ArchiveFilter = .all
    @State private var searchQuery: String = ""

    @State private var isCheckingNew: Bool = false
    @State private var isResyncingAll: Bool = false
    @State private var resyncingIDs: Set<String> = []
    @State private var queuedNoticeIDs: Set<String> = []
    @State private var statusBannerText: String = ""
    @State private var statusBannerIsError: Bool = false

    public init() {}

    private var activeList: [PlaylistItem] {
        let raw: [PlaylistItem]
        switch selectedSource {
        case .spotify: raw = api.spotifyPlaylists
        case .imported: raw = api.importedPlaylists
        case .vault: raw = api.vaultPlaylists
        }

        return raw.filter { item in
            let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !q.isEmpty {
                let matchName = item.displayName.lowercased().contains(q)
                let matchSlug = item.effectiveSlug.lowercased().contains(q)
                if !matchName && !matchSlug { return false }
            }
            switch selectedFilter {
            case .all: return true
            case .synced: return item.effectiveSynced
            case .unsynced: return !item.effectiveSynced
            case .publicOnly: return item.isPublic
            case .privateOnly: return !item.isPublic
            }
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // MARK: Pinned Top Control Header
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("[ SEC-03 // HOLOCRON ] // \(activeList.count) ARCHIVES")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(theme.accent)
                            .lineLimit(1)
                        Text("HOLOCRON ARCHIVES.")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(theme.fgPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer()
                }

                // Source Switcher Pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        sourceButton(.spotify, count: api.spotifyPlaylists.count)
                        sourceButton(.imported, count: api.importedPlaylists.count)
                        sourceButton(.vault, count: api.vaultPlaylists.count)
                    }
                }

                // Global Action Row: Check New Playlists + Re-Sync All
                HStack(spacing: 8) {
                    Button {
                        runCheckNewPlaylists()
                    } label: {
                        Text(isCheckingNew ? "✦ CHECKING..." : "✦ CHECK NEW")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.cyan.opacity(0.14))
                            .foregroundStyle(Color.cyan)
                            .overlay(ChamferedRectangle(cut: 6).stroke(Color.cyan.opacity(0.6), lineWidth: 1))
                            .clipShape(ChamferedRectangle(cut: 6))
                    }
                    .disabled(isCheckingNew)

                    Button {
                        runResyncAll()
                    } label: {
                        Text(isResyncingAll ? "↻ QUEUING..." : "↻ RE-SYNC ALL")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(theme.accent.opacity(0.15))
                            .foregroundStyle(theme.accent)
                            .overlay(ChamferedRectangle(cut: 6).stroke(theme.accent.opacity(0.65), lineWidth: 1))
                            .clipShape(ChamferedRectangle(cut: 6))
                    }
                    .disabled(isResyncingAll)
                }

                // Dismissible Status / Discovery Banner
                if !statusBannerText.isEmpty {
                    HStack(spacing: 8) {
                        Text(statusBannerText)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(statusBannerIsError ? .red : theme.accent)
                            .lineLimit(2)
                        Spacer(minLength: 4)
                        Button {
                            statusBannerText = ""
                        } label: {
                            Text("✕")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(statusBannerIsError ? .red : theme.fgMuted)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background((statusBannerIsError ? Color.red : theme.accent).opacity(0.12))
                    .overlay(Rectangle().stroke((statusBannerIsError ? Color.red : theme.accent).opacity(0.45), lineWidth: 1))
                }

                // Filter Pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(ArchiveFilter.allCases, id: \.self) { filter in
                            Button {
                                selectedFilter = filter
                            } label: {
                                Text(filter.rawValue)
                                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(selectedFilter == filter ? theme.accent.opacity(0.2) : Color.clear)
                                    .foregroundStyle(selectedFilter == filter ? theme.accent : theme.fgMuted)
                                    .overlay(ChamferedRectangle(cut: 5).stroke(selectedFilter == filter ? theme.accent : theme.hairline, lineWidth: 1))
                            }
                        }
                    }
                }

                // Search Bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.accent)
                    TextField("FILTER BY PLAYLIST OR SLUG...", text: $searchQuery)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(theme.fgPrimary)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !searchQuery.isEmpty {
                        Button { searchQuery = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(theme.fgMuted)
                        }
                    }
                }
                .padding(.vertical, 6)
                .overlay(alignment: .bottom) { Rectangle().fill(theme.hairline).frame(height: 1) }
            }

            // MARK: Contained Scrollable Playlist Viewport
            Group {
                if activeList.isEmpty {
                    VStack {
                        Spacer()
                        Text("[ NO ARCHIVES MATCHING CURRENT SECTOR PARAMETERS ]")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(theme.fgMuted)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(Array(activeList.enumerated()), id: \.element.id) { idx, item in
                                holocronPlaylistRow(index: idx + 1, item: item)
                            }
                        }
                        .padding(10)
                        .padding(.bottom, 70)
                    }
                    .refreshable {
                        await api.fetchAllPlaylists()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(theme.isHangarLightPolarity ? 0.04 : 0.42))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.hairline, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sourceButton(_ source: ArchiveSource, count: Int) -> some View {
        let isSelected = selectedSource == source
        return Button {
            selectedSource = source
            theme.triggerScreenTransitionFX()
        } label: {
            Text("\(source.rawValue) (\(count))")
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? theme.accent : Color.clear)
                .foregroundStyle(isSelected ? .black : theme.fgMuted)
                .overlay(ChamferedRectangle(cut: 7).stroke(isSelected ? theme.accent : theme.hairline, lineWidth: 1))
                .clipShape(ChamferedRectangle(cut: 7))
        }
    }

    private func holocronPlaylistRow(index: Int, item: PlaylistItem) -> some View {
        let spKey = item.effectiveSpotifyID ?? item.id
        let isNewlyFound = api.newlyDiscoveredPlaylistIDs.contains(spKey)
        let isResyncing = resyncingIDs.contains(item.id)
        let isQueuedNotice = queuedNoticeIDs.contains(item.id)

        return VStack(alignment: .leading, spacing: 10) {
            // Top Row: Index + Artwork + Clickable Title (Feishin) + Dedicated SPOTIFY ↗ Button
            HStack(spacing: 10) {
                Text(String(format: "%02d", index))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.accent)
                    .frame(width: 22, alignment: .leading)

                AsyncImage(url: URL(string: item.displayCover ?? "")) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(theme.hairline)
                }
                .frame(width: 40, height: 40)
                .border(theme.hairline, width: 1)
                .clipped()

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Button {
                            if let amperfyURL = URL(string: "amperfy://") {
                                openURL(amperfyURL) { accepted in
                                    if !accepted, let fallback = api.feishinPlayerURL {
                                        openURL(fallback)
                                    }
                                }
                            }
                        } label: {
                            Text(item.displayName)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(theme.fgPrimary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .buttonStyle(.plain)

                        if isNewlyFound {
                            Text("NEW")
                                .font(.system(size: 8.5, weight: .heavy, design: .monospaced))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.cyan)
                                .foregroundStyle(.black)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }

                        if let spotifyURL = item.spotifyWebURL {
                            Button {
                                openURL(spotifyURL)
                            } label: {
                                Text("SPOTIFY ↗")
                                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2.5)
                                    .background(Color(red: 0.11, green: 0.73, blue: 0.33).opacity(0.16))
                                    .foregroundStyle(Color(red: 0.11, green: 0.73, blue: 0.33))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 3)
                                            .stroke(Color(red: 0.11, green: 0.73, blue: 0.33).opacity(0.55), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            .fixedSize()
                        }

                        Spacer(minLength: 0)
                    }

                    Text("/playlists/\(item.effectiveSlug) • 👤 \(item.displayOwner)")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(theme.accent)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Progress Bar
            VStack(spacing: 4) {
                HStack {
                    Text("\(item.effectiveDownloaded) / \(item.effectiveTotal) TRACKS")
                    Spacer()
                    Text("\(item.progressPercent)%")
                        .foregroundStyle(theme.accent)
                }
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme.fgMuted)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(theme.hairline).frame(height: 3)
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: geo.size.width * item.progressFraction, height: 3)
                            .shadow(color: theme.accent, radius: 6)
                    }
                }
                .frame(height: 3)
            }

            // Action Bar: Sync Switch, Visibility, ↻ RE-SYNC, Delete
            HStack(spacing: 8) {
                Button {
                    Task {
                        await api.configurePlaylist(
                            item: item,
                            isSynced: !item.effectiveSynced,
                            visibility: item.visibility ?? "private"
                        )
                    }
                } label: {
                    HStack(spacing: 5) {
                        ZStack(alignment: item.effectiveSynced ? .trailing : .leading) {
                            ChamferedRectangle(cut: 4)
                                .fill(item.effectiveSynced ? theme.accent.opacity(0.22) : Color.white.opacity(0.06))
                                .frame(width: 34, height: 17)
                                .overlay(ChamferedRectangle(cut: 4).stroke(item.effectiveSynced ? theme.accent : theme.hairline, lineWidth: 1))
                            Rectangle()
                                .fill(item.effectiveSynced ? Color.white : theme.fgMuted)
                                .frame(width: 11, height: 11)
                                .padding(.horizontal, 3)
                                .shadow(color: item.effectiveSynced ? theme.accent : .clear, radius: 4)
                        }
                        Text(item.effectiveSynced ? "SYNC ON" : "SYNC OFF")
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(item.effectiveSynced ? theme.accent : theme.fgMuted)
                    }
                }

                Spacer(minLength: 2)

                Button {
                    let nextVis = item.isPublic ? "private" : "public"
                    Task {
                        await api.configurePlaylist(item: item, isSynced: item.effectiveSynced, visibility: nextVis)
                    }
                } label: {
                    Text(item.isPublic ? "🌍 PUBLIC" : "🔒 PRIVATE")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .foregroundStyle(theme.fgPrimary)
                        .overlay(ChamferedRectangle(cut: 5).stroke(theme.hairline, lineWidth: 1))
                }

                Button {
                    runResyncSingle(item)
                } label: {
                    Text(isResyncing ? "↻ ..." : (isQueuedNotice ? "✓ QUEUED" : "↻ RE-SYNC"))
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(theme.accent.opacity(0.12))
                        .foregroundStyle(theme.accent)
                        .overlay(ChamferedRectangle(cut: 5).stroke(theme.accent, lineWidth: 1))
                }
                .disabled(isResyncing)

                Button {
                    Task { await api.deletePlaylistFromProfile(item: item) }
                } label: {
                    Text("✕")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .foregroundStyle(.red)
                        .overlay(ChamferedRectangle(cut: 5).stroke(Color.red.opacity(0.7), lineWidth: 1))
                }
            }
        }
        .padding(12)
        .background(theme.bgElevated)
        .overlay(
            ChamferedRectangle(cut: 12)
                .stroke(isNewlyFound ? Color.cyan : theme.hairline, lineWidth: isNewlyFound ? 1.5 : 1)
        )
        .clipShape(ChamferedRectangle(cut: 12))
    }

    private func runResyncSingle(_ item: PlaylistItem) {
        resyncingIDs.insert(item.id)
        theme.triggerScreenTransitionFX()
        Task {
            _ = await api.resyncPlaylist(item: item)
            await MainActor.run {
                resyncingIDs.remove(item.id)
                queuedNoticeIDs.insert(item.id)
            }
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            await MainActor.run {
                queuedNoticeIDs.remove(item.id)
            }
        }
    }

    private func runResyncAll() {
        isResyncingAll = true
        statusBannerIsError = false
        Task {
            do {
                let res = try await api.resyncAllPlaylists()
                let cnt = res.queued_count ?? 0
                await MainActor.run {
                    statusBannerText = cnt > 0
                        ? "✓ QUEUED \(cnt) PLAYLIST\(cnt == 1 ? "" : "S") FOR FRESH SPOTIFY RE-SYNC"
                        : "NO SYNCED PLAYLISTS FOUND — ENABLE SYNC ON A PLAYLIST FIRST"
                    isResyncingAll = false
                    theme.triggerScreenTransitionFX()
                }
            } catch {
                await MainActor.run {
                    statusBannerIsError = true
                    statusBannerText = "✕ RE-SYNC ALL FAILED: \(error.localizedDescription.uppercased())"
                    isResyncingAll = false
                }
            }
        }
    }

    private func runCheckNewPlaylists() {
        isCheckingNew = true
        statusBannerIsError = false
        Task {
            do {
                let res = try await api.checkNewSpotifyPlaylists()
                let newCnt = res.new_count ?? 0
                let totalCnt = res.total_count ?? api.spotifyPlaylists.count
                await MainActor.run {
                    if newCnt > 0 {
                        let names = (res.new_playlists ?? []).prefix(3).map { "\"\($0.name)\"" }.joined(separator: ", ")
                        statusBannerText = "✓ FOUND \(newCnt) NEW PLAYLIST\(newCnt == 1 ? "" : "S"): \(names)"
                    } else {
                        statusBannerText = "✓ SPOTIFY ACCOUNT UP TO DATE (\(totalCnt) PLAYLISTS)"
                    }
                    isCheckingNew = false
                    theme.triggerScreenTransitionFX()
                }
            } catch {
                await MainActor.run {
                    statusBannerIsError = true
                    statusBannerText = "✕ CHECK FAILED: \(error.localizedDescription.uppercased())"
                    isCheckingNew = false
                }
            }
        }
    }
}
