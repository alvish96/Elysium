import SwiftUI

public struct CatalogSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var theme
    @Environment(APIClient.self) private var apiClient

    public var onPlaylistImported: (() -> Void)?

    @State private var searchQuery: String = ""
    @State private var searchResults: [PublicSpotifyPlaylist] = []
    @State private var isSearching: Bool = false
    @State private var errorMessage: String? = nil

    // In-flight status per playlist ID ("syncing", "importing", "done", "error")
    @State private var itemStates: [String: String] = [:]

    public init(onPlaylistImported: (() -> Void)? = nil) {
        self.onPlaylistImported = onPlaylistImported
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                AppCanvasBackgroundView()

                VStack(spacing: 0) {
                    // Search Bar Header
                    searchHeaderView
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
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(hex: "#F43F5E").opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    }

                    // Results or Placeholders
                    if isSearching {
                        VStack(spacing: 12) {
                            Spacer()
                            ProgressView()
                                .tint(theme.accentEmerald)
                                .scaleEffect(1.2)
                            Text("Querying Spotify Public Catalog...")
                                .font(.subheadline)
                                .foregroundStyle(theme.secondaryText)
                            Spacer()
                        }
                    } else if searchResults.isEmpty {
                        VStack(spacing: 12) {
                            Spacer()
                            Image(systemName: "magnifyingglass.circle")
                                .font(.system(size: 52))
                                .foregroundStyle(theme.mutedText)
                            Text("Search Millions of Spotify Playlists")
                                .font(.headline)
                                .foregroundStyle(theme.primaryText)
                            Text("Search by mood, artist, genre, or keyword to import directly into your library.")
                                .font(.footnote)
                                .foregroundStyle(theme.secondaryText)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                            Spacer()
                        }
                    } else {
                        ScrollView {
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 300, maximum: 500), spacing: 14)],
                                spacing: 14
                            ) {
                                ForEach(searchResults) { playlist in
                                    catalogItemCard(playlist)
                                }
                            }
                            .padding(16)
                        }
                    }
                }
            }
            .navigationTitle("Global Spotify Catalog")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.accentEmerald)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Search Header View

    private var searchHeaderView: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.subheadline)
                    .foregroundStyle(theme.mutedText)

                TextField("Search global Spotify playlists...", text: $searchQuery)
                    .font(.subheadline)
                    .foregroundStyle(theme.primaryText)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .onSubmit {
                        performSearch()
                    }

                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(theme.mutedText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(theme.inputBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(theme.cardBorder, lineWidth: 1.0)
            )

            Button {
                performSearch()
            } label: {
                Text("Search")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(theme.accentEmerald)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(searchQuery.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
        }
    }

    // MARK: - Item Card View

    @ViewBuilder
    private func catalogItemCard(_ item: PublicSpotifyPlaylist) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                // Cover Art
                AsyncImage(url: URL(string: item.cover_url ?? "")) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure, .empty:
                        ZStack {
                            Rectangle().fill(theme.cardBorder.opacity(0.3))
                            Image(systemName: "music.note.list")
                                .foregroundStyle(theme.mutedText)
                        }
                    @unknown default:
                        Rectangle().fill(theme.cardBorder.opacity(0.3))
                    }
                }
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(theme.cardBorder, lineWidth: 0.8)
                )

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)

                    if let owner = item.owner_name {
                        Text("By \(owner)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(1)
                    }

                    if let total = item.total_tracks {
                        Text("\(total) tracks")
                            .font(.caption2.monospaced())
                            .foregroundStyle(theme.accentEmerald)
                    }
                }

                Spacer()
            }

            if let desc = item.description, !desc.isEmpty {
                Text(desc.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
                    .font(.caption2)
                    .foregroundStyle(theme.mutedText)
                    .lineLimit(2)
            }

            Divider()
                .background(theme.cardBorder)

            // Bottom 1-Tap Action Buttons
            let state = itemStates[item.id] ?? "idle"

            if state == "done" {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.accentEmerald)
                    Text("Imported to Library")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(theme.accentEmerald)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(theme.accentEmeraldGlow)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                HStack(spacing: 8) {
                    // Import Only Button
                    Button {
                        importCatalogItem(item, autoSync: false)
                    } label: {
                        HStack(spacing: 4) {
                            if state == "importing" {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .tint(theme.primaryText)
                            } else {
                                Image(systemName: "bookmark")
                                    .font(.system(size: 10))
                                Text("Import Only")
                                    .font(.caption2.weight(.bold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(theme.pillBackground)
                        .foregroundStyle(theme.primaryText)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(theme.cardBorder, lineWidth: 0.8)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(state != "idle")

                    // Import & Sync Button
                    Button {
                        importCatalogItem(item, autoSync: true)
                    } label: {
                        HStack(spacing: 4) {
                            if state == "syncing" {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .tint(.white)
                            } else {
                                Image(systemName: "cloud.arrow.down.fill")
                                    .font(.system(size: 10))
                                Text("Import & Sync")
                                    .font(.caption2.weight(.bold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(theme.accentEmerald)
                        .foregroundStyle(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .disabled(state != "idle")
                }
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 16, padding: nil)
    }

    // MARK: - Actions

    private func performSearch() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        isSearching = true
        errorMessage = nil

        Task {
            do {
                let results = try await apiClient.searchPublicSpotifyCatalog(query: query)
                await MainActor.run {
                    self.searchResults = results
                    self.isSearching = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isSearching = false
                }
            }
        }
    }

    private func importCatalogItem(_ playlist: PublicSpotifyPlaylist, autoSync: Bool) {
        itemStates[playlist.id] = autoSync ? "syncing" : "importing"

        Task {
            do {
                _ = try await apiClient.importPlaylist(
                    urlOrId: playlist.id,
                    visibility: "private",
                    autoSync: autoSync
                )
                await MainActor.run {
                    itemStates[playlist.id] = "done"
                    onPlaylistImported?()
                }
            } catch {
                await MainActor.run {
                    itemStates[playlist.id] = "idle"
                    errorMessage = "Failed to import \(playlist.name): \(error.localizedDescription)"
                }
            }
        }
    }
}
