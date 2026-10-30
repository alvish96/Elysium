import SwiftUI
import Observation
import Combine

public enum SyncLibraryTab: String, CaseIterable, Identifiable, Sendable {
    case spotify = "Spotify Account"
    case imported = "Imported Links"
    case vault = "Server Vault"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .spotify: return "music.note"
        case .imported: return "link"
        case .vault: return "server.rack"
        }
    }
}

public struct SyncLibraryTabsView: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(APIClient.self) private var apiClient
    @Environment(WebSocketManager.self) private var wsManager

    public var targetTab: SyncLibraryTab?
    public var onSelectPlaylist: ((PlaylistItem) -> Void)?

    @State private var internalSelectedTab: SyncLibraryTab = .spotify
    @State private var playlists: [PlaylistItem] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var importedCount: Int = 0

    // Filter, Sort & View Controls
    @State private var searchText: String = ""
    @State private var sortOption: SortOption = .nameAsc
    @State private var filterOption: FilterOption = .all
    @State private var viewMode: ViewMode = .grid
    @State private var columnConfig: TableColumnConfig = .default

    // Sheets
    @State private var showImportModal: Bool = false
    @State private var showCatalogSearchModal: Bool = false
    @State private var cancellables = Set<AnyCancellable>()

    public init(
        targetTab: SyncLibraryTab? = nil,
        onSelectPlaylist: ((PlaylistItem) -> Void)? = nil
    ) {
        self.targetTab = targetTab
        self.onSelectPlaylist = onSelectPlaylist
    }

    private var activeTab: SyncLibraryTab {
        targetTab ?? internalSelectedTab
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                AppCanvasBackgroundView()

                VStack(spacing: 0) {
                    // Integrated Top Header & Sub-Toolbar
                    TopHeaderAndToolbarView(
                        searchText: $searchText,
                        sortOption: $sortOption,
                        filterOption: $filterOption,
                        viewMode: $viewMode,
                        columnConfig: $columnConfig,
                        totalCount: playlists.count,
                        filteredCount: processedPlaylists.count,
                        suggestions: autocompleteSuggestions,
                        onSelectSuggestion: { item in
                            onSelectPlaylist?(item)
                        },
                        onRefresh: {
                            Task { await loadCurrentTabPlaylists() }
                        },
                        onOpenImport: {
                            showImportModal = true
                        },
                        onOpenCatalogSearch: {
                            showCatalogSearchModal = true
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 12)

                    // Optional 3-Tab Pill Switcher (Rendered if view is acting as unified root)
                    if targetTab == nil {
                        tabSelectorPillBar
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                    }

                    // Error Alert Bar
                    if let err = errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.octagon.fill")
                                .foregroundStyle(Color(hex: "#F43F5E"))
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(Color(hex: "#F43F5E"))
                            Spacer()
                            Button {
                                errorMessage = nil
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2)
                                    .foregroundStyle(Color(hex: "#F43F5E"))
                            }
                        }
                        .padding(10)
                        .background(Color(hex: "#F43F5E").opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    }

                    // Content Area: Grid or Table
                    if isLoading && playlists.isEmpty {
                        VStack(spacing: 12) {
                            Spacer()
                            ProgressView()
                                .tint(theme.accentEmerald)
                                .scaleEffect(1.2)
                            Text("Loading \(activeTab.rawValue)...")
                                .font(.subheadline)
                                .foregroundStyle(theme.secondaryText)
                            Spacer()
                        }
                    } else if processedPlaylists.isEmpty {
                        emptyStateView
                    } else {
                        ScrollView {
                            if viewMode == .grid {
                                gridView
                                    .padding(16)
                            } else {
                                tableView
                                    .padding(16)
                            }
                        }
                        .refreshable {
                            await loadCurrentTabPlaylists()
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showImportModal) {
                ImportPlaylistSheet { _ in
                    Task {
                        await loadCurrentTabPlaylists()
                    }
                }
            }
            .sheet(isPresented: $showCatalogSearchModal) {
                CatalogSearchSheet {
                    Task {
                        await loadCurrentTabPlaylists()
                    }
                }
            }
            .task {
                await loadCurrentTabPlaylists()
                subscribeToWebSocketEvents()
            }
            .onChange(of: internalSelectedTab) { _, _ in
                Task {
                    playlists.removeAll()
                    await loadCurrentTabPlaylists()
                }
            }
        }
    }

    // MARK: - Tab Selector Bar

    private var tabSelectorPillBar: some View {
        HStack(spacing: 6) {
            ForEach(SyncLibraryTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        internalSelectedTab = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 11, weight: .bold))

                        Text(tab.rawValue)
                            .font(.caption.weight(.bold))

                        if tab == .imported && importedCount > 0 {
                            Text("\(importedCount)")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(internalSelectedTab == .imported ? Color.black.opacity(0.3) : theme.accentEmeraldGlow)
                                .foregroundStyle(internalSelectedTab == .imported ? Color.white : theme.accentEmerald)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(internalSelectedTab == tab ? theme.accentEmerald : theme.cardBackground)
                    .foregroundStyle(internalSelectedTab == tab ? Color.white : theme.secondaryText)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(internalSelectedTab == tab ? theme.accentEmerald : theme.cardBorder, lineWidth: 1.0)
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: - Grid View

    private var gridView: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 310, maximum: 460), spacing: 14)],
            spacing: 14
        ) {
            ForEach(processedPlaylists) { item in
                PlaylistGridCardView(
                    playlist: item,
                    showDeleteButton: activeTab == .imported,
                    onToggleSync: { isSynced in
                        mutatePlaylistConfig(playlist: item, isSynced: isSynced, visibility: item.visibility ?? "private")
                    },
                    onChangeVisibility: { newVis in
                        mutatePlaylistConfig(playlist: item, isSynced: item.isSyncedBool, visibility: newVis)
                    },
                    onSyncNow: {
                        triggerSync(item)
                    },
                    onDelete: {
                        deletePlaylist(item)
                    },
                    onTapCard: {
                        onSelectPlaylist?(item)
                    }
                )
            }
        }
    }

    // MARK: - Table View with Sortable Column Headers

    private var tableView: some View {
        VStack(spacing: 8) {
            // Sortable Table Header Row
            HStack(spacing: 12) {
                if columnConfig.showCover {
                    Text("Cover")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(theme.mutedText)
                        .frame(width: 44, alignment: .leading)
                }

                // Title Sortable Header
                Button {
                    sortOption = (sortOption == .nameAsc) ? .nameDesc : .nameAsc
                } label: {
                    HStack(spacing: 3) {
                        Text("Title")
                            .font(.caption2.weight(.bold))
                        headerSortChevron(forAsc: .nameAsc, forDesc: .nameDesc)
                    }
                    .foregroundStyle(sortOption == .nameAsc || sortOption == .nameDesc ? theme.accentEmerald : theme.mutedText)
                }
                .buttonStyle(.plain)
                .frame(minWidth: 110, alignment: .leading)

                Spacer()

                if columnConfig.showOwner {
                    Button {
                        sortOption = .ownerAsc
                    } label: {
                        HStack(spacing: 3) {
                            Text("Owner")
                                .font(.caption2.weight(.bold))
                            if sortOption == .ownerAsc {
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 8, weight: .bold))
                            }
                        }
                        .foregroundStyle(sortOption == .ownerAsc ? theme.accentEmerald : theme.mutedText)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 80, alignment: .center)
                }

                if columnConfig.showTracks {
                    Button {
                        sortOption = (sortOption == .tracksDesc) ? .tracksAsc : .tracksDesc
                    } label: {
                        HStack(spacing: 3) {
                            Text("Tracks")
                                .font(.caption2.weight(.bold))
                            headerSortChevron(forAsc: .tracksAsc, forDesc: .tracksDesc)
                        }
                        .foregroundStyle(sortOption == .tracksDesc || sortOption == .tracksAsc ? theme.accentEmerald : theme.mutedText)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 65, alignment: .trailing)
                }

                if columnConfig.showStatus {
                    Text("Status")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(theme.mutedText)
                        .frame(width: 100, alignment: .trailing)
                }

                if columnConfig.showVisibility {
                    Text("Visibility")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(theme.mutedText)
                        .frame(width: 70, alignment: .center)
                }

                if columnConfig.showActions {
                    Text("Actions")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(theme.mutedText)
                        .frame(width: 80, alignment: .trailing)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(theme.inputBackground.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Rows
            LazyVStack(spacing: 8) {
                ForEach(processedPlaylists) { item in
                    PlaylistTableRowView(
                        playlist: item,
                        columns: columnConfig,
                        showDeleteButton: activeTab == .imported,
                        onToggleSync: { isSynced in
                            mutatePlaylistConfig(playlist: item, isSynced: isSynced, visibility: item.visibility ?? "private")
                        },
                        onChangeVisibility: { newVis in
                            mutatePlaylistConfig(playlist: item, isSynced: item.isSyncedBool, visibility: newVis)
                        },
                        onSyncNow: {
                            triggerSync(item)
                        },
                        onDelete: {
                            deletePlaylist(item)
                        },
                        onTapRow: {
                            onSelectPlaylist?(item)
                        }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func headerSortChevron(forAsc: SortOption, forDesc: SortOption) -> some View {
        if sortOption == forAsc {
            Image(systemName: "chevron.up")
                .font(.system(size: 8, weight: .bold))
        } else if sortOption == forDesc {
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
        } else {
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 7))
                .opacity(0.3)
        }
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 14) {
            Spacer()

            ZStack {
                Circle()
                    .fill(theme.cardBackground)
                    .frame(width: 80, height: 80)
                Image(systemName: activeTab.iconName)
                    .font(.system(size: 34))
                    .foregroundStyle(theme.accentEmerald)
            }

            Text("No Playlists in \(activeTab.rawValue)")
                .font(.headline.weight(.bold))
                .foregroundStyle(theme.primaryText)

            Text(emptyStateDescription)
                .font(.footnote)
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)

            Button {
                showImportModal = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text("Import Spotify Playlist")
                }
                .font(.subheadline.weight(.bold))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(theme.accentEmerald)
                .foregroundStyle(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.top, 6)

            Spacer()
        }
    }

    private var emptyStateDescription: String {
        switch activeTab {
        case .spotify:
            return "No playlists found on your connected Spotify account, or your account may be limited by OAuth whitelist limits."
        case .imported:
            return "No URL-imported playlists yet. Paste any public or unlisted Spotify playlist link to get started."
        case .vault:
            return "No playlists currently synchronized to the physical server vault on Atlantis."
        }
    }

    // MARK: - Filtering, Sorting & Search

    private var autocompleteSuggestions: [PlaylistItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return playlists.filter {
            $0.name.lowercased().contains(q) ||
            $0.effectiveFolderSlug.lowercased().contains(q) ||
            $0.effectiveOwner.lowercased().contains(q)
        }
    }

    private var processedPlaylists: [PlaylistItem] {
        var result = playlists

        // 1. Text Search Filter
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            result = result.filter {
                $0.name.lowercased().contains(q) ||
                $0.effectiveFolderSlug.lowercased().contains(q) ||
                $0.effectiveOwner.lowercased().contains(q)
            }
        }

        // 2. Filter Menu Option
        switch filterOption {
        case .all:
            break
        case .synced:
            result = result.filter { $0.isSyncedBool }
        case .unsynced:
            result = result.filter { !$0.isSyncedBool }
        case .privateOnly:
            result = result.filter { !$0.isPublic }
        case .publicOnly:
            result = result.filter { $0.isPublic }
        }

        // 3. Sorting
        switch sortOption {
        case .nameAsc:
            result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .nameDesc:
            result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        case .ownerAsc:
            result.sort { $0.effectiveOwner.localizedCaseInsensitiveCompare($1.effectiveOwner) == .orderedAscending }
        case .tracksDesc:
            result.sort { $0.effectiveTotalTracks > $1.effectiveTotalTracks }
        case .tracksAsc:
            result.sort { $0.effectiveTotalTracks < $1.effectiveTotalTracks }
        }

        return result
    }

    // MARK: - Networking & Operations

    private func loadCurrentTabPlaylists() async {
        isLoading = true
        errorMessage = nil

        do {
            switch activeTab {
            case .spotify:
                let items = try await apiClient.fetchSpotifyAccountPlaylists()
                await MainActor.run {
                    self.playlists = items
                    self.isLoading = false
                }
            case .imported:
                let items = try await apiClient.fetchImportedPlaylists()
                await MainActor.run {
                    self.playlists = items
                    self.importedCount = items.count
                    self.isLoading = false
                }
            case .vault:
                let items = try await apiClient.fetchVaultPlaylists()
                await MainActor.run {
                    self.playlists = items
                    self.isLoading = false
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    private func mutatePlaylistConfig(playlist: PlaylistItem, isSynced: Bool, visibility: String) {
        if let idx = playlists.firstIndex(where: { $0.id == playlist.id }) {
            playlists[idx].is_synced = isSynced
            playlists[idx].visibility = visibility
        }

        Task {
            do {
                try await apiClient.configurePlaylist(
                    spotifyId: playlist.effectiveSpotifyId,
                    isSynced: isSynced,
                    visibility: visibility,
                    folderSlug: playlist.folder_slug
                )
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to update configuration: \(error.localizedDescription)"
                }
            }
        }
    }

    private func triggerSync(_ playlist: PlaylistItem) {
        Task {
            do {
                try await apiClient.triggerSyncNow(spotifyId: playlist.effectiveSpotifyId)
                await MainActor.run {
                    if let idx = playlists.firstIndex(where: { $0.id == playlist.id }) {
                        playlists[idx].sync_status = "queued"
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to trigger sync: \(error.localizedDescription)"
                }
            }
        }
    }

    private func deletePlaylist(_ playlist: PlaylistItem) {
        Task {
            do {
                try await apiClient.deleteImportedPlaylist(spotifyId: playlist.effectiveSpotifyId)
                await MainActor.run {
                    playlists.removeAll(where: { $0.id == playlist.id })
                    importedCount = playlists.count
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to delete playlist: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Live WebSocket Subscription

    private func subscribeToWebSocketEvents() {
        cancellables.removeAll()

        wsManager.eventSubject
            .receive(on: DispatchQueue.main)
            .sink { [self] event in
                handleIncomingWSEvent(event)
            }
            .store(in: &cancellables)
    }

    private func handleIncomingWSEvent(_ event: WSEvent) {
        guard let pid = event.playlist_id else { return }

        guard let idx = playlists.firstIndex(where: {
            $0.id == pid ||
            $0.spotify_playlist_id == pid ||
            $0.folder_slug == event.folder_slug
        }) else { return }

        switch event.event {
        case "TRACK_PROGRESS":
            if let downloaded = event.downloaded_count ?? event.current {
                playlists[idx].downloaded_tracks = downloaded
            }
            if let total = event.total {
                playlists[idx].total_tracks = total
            }
            playlists[idx].sync_status = "syncing"

        case "SYNC_COMPLETED":
            if let downloaded = event.downloaded_count {
                playlists[idx].downloaded_tracks = downloaded
            }
            if let total = event.total {
                playlists[idx].total_tracks = total
            }
            playlists[idx].sync_status = "completed"

        case "PLAYLIST_CONFIGURED":
            if let synced = event.is_synced {
                playlists[idx].is_synced = synced
            }
            if let vis = event.visibility {
                playlists[idx].visibility = vis
            }
            if let slug = event.folder_slug {
                playlists[idx].folder_slug = slug
            }

        case "PLAYLIST_QUEUED":
            playlists[idx].sync_status = "queued"

        default:
            break
        }
    }
}
