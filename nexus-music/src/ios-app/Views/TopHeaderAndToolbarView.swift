import SwiftUI
import Observation

// MARK: - Smooth Sliding Theme Toggle Switch

public struct ThemeSliderSwitch: View {
    @Environment(ThemeManager.self) private var theme

    public init() {}

    public var body: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                theme.isLightMode.toggle()
            }
        } label: {
            ZStack {
                // Capsule Track
                Capsule()
                    .fill(theme.inputBackground)
                    .frame(width: 62, height: 32)
                    .overlay(
                        Capsule()
                            .strokeBorder(theme.cardBorder, lineWidth: 1.0)
                    )

                // Animated Sliding Knob
                HStack {
                    if theme.isLightMode {
                        Circle()
                            .fill(Color(hex: "#F59E0B"))
                            .frame(width: 26, height: 26)
                            .shadow(color: Color(hex: "#F59E0B").opacity(0.4), radius: 4, x: 0, y: 1)
                            .overlay(
                                Image(systemName: "sun.max.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Color.white)
                            )
                            .transition(.identity)

                        Spacer()
                    } else {
                        Spacer()

                        Circle()
                            .fill(Color(hex: "#6366F1"))
                            .frame(width: 26, height: 26)
                            .shadow(color: Color(hex: "#6366F1").opacity(0.4), radius: 4, x: 0, y: 1)
                            .overlay(
                                Image(systemName: "moon.stars.fill")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Color.white)
                            )
                            .transition(.identity)
                    }
                }
                .padding(.horizontal, 3)
                .frame(width: 62, height: 32)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Top Header & Sub-Toolbar Combined Component

public struct TopHeaderAndToolbarView: View {
    @Environment(ThemeManager.self) private var theme

    @Binding public var searchText: String
    @Binding public var sortOption: SortOption
    @Binding public var filterOption: FilterOption
    @Binding public var viewMode: ViewMode
    @Binding public var columnConfig: TableColumnConfig

    public var totalCount: Int
    public var filteredCount: Int
    public var suggestions: [PlaylistItem]
    public var onSelectSuggestion: ((PlaylistItem) -> Void)?
    public var onRefresh: () -> Void
    public var onOpenImport: () -> Void
    public var onOpenCatalogSearch: () -> Void

    @State private var spinAngle: Double = 0.0
    @State private var isSearchFocused: Bool = false
    @FocusState private var searchFieldFocused: Bool

    public init(
        searchText: Binding<String>,
        sortOption: Binding<SortOption>,
        filterOption: Binding<FilterOption>,
        viewMode: Binding<ViewMode>,
        columnConfig: Binding<TableColumnConfig>,
        totalCount: Int,
        filteredCount: Int,
        suggestions: [PlaylistItem] = [],
        onSelectSuggestion: ((PlaylistItem) -> Void)? = nil,
        onRefresh: @escaping () -> Void,
        onOpenImport: @escaping () -> Void,
        onOpenCatalogSearch: @escaping () -> Void
    ) {
        self._searchText = searchText
        self._sortOption = sortOption
        self._filterOption = filterOption
        self._viewMode = viewMode
        self._columnConfig = columnConfig
        self.totalCount = totalCount
        self.filteredCount = filteredCount
        self.suggestions = suggestions
        self.onSelectSuggestion = onSelectSuggestion
        self.onRefresh = onRefresh
        self.onOpenImport = onOpenImport
        self.onOpenCatalogSearch = onOpenCatalogSearch
    }

    public var body: some View {
        VStack(spacing: 12) {
            // MARK: - Top Header Bar
            HStack(spacing: 12) {
                // Left: Gradient Brand Title with 360-degree Animated Refresh Spin
                Button {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        spinAngle += 360.0
                    }
                    onRefresh()
                } label: {
                    HStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [theme.accentEmerald, Color(hex: "#34D399")],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 34, height: 34)
                                .shadow(color: theme.accentEmerald.opacity(0.35), radius: 6, x: 0, y: 2)

                            Image(systemName: "music.note")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Color.black)
                                .rotationEffect(.degrees(spinAngle))
                        }

                        VStack(alignment: .leading, spacing: 0) {
                            Text("Nexus Music")
                                .font(.system(size: 17, weight: .black, design: .rounded))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [theme.primaryText, theme.accentEmerald],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )

                            Text("K3s Audio Controller")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(theme.mutedText)
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer(minLength: 8)

                // Center: Universal Search Field + Autocomplete Anchor + Search API Button
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.caption)
                            .foregroundStyle(theme.mutedText)

                        TextField("Search playlists, slugs, owners...", text: $searchText)
                            .font(.subheadline)
                            .foregroundStyle(theme.primaryText)
                            .focused($searchFieldFocused)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .onChange(of: searchFieldFocused) { _, focused in
                                isSearchFocused = focused
                            }

                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(theme.mutedText)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(theme.inputBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(theme.cardBorder, lineWidth: 1.0)
                    )

                    // Search Global Spotify API Shortcut Button
                    Button {
                        searchFieldFocused = false
                        onOpenCatalogSearch()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "globe.americas.fill")
                                .font(.caption2)
                            Text("Search API")
                                .font(.caption2.weight(.bold))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 8)
                        .background(theme.accentEmeraldGlow)
                        .foregroundStyle(theme.accentEmerald)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(theme.accentEmerald.opacity(0.4), lineWidth: 0.8)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: 440)

                Spacer(minLength: 8)

                // Right: Sun/Moon Theme Slider + Import Button
                HStack(spacing: 10) {
                    ThemeSliderSwitch()

                    Button {
                        onOpenImport()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .bold))
                            Text("Import")
                                .font(.caption.weight(.bold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(theme.accentEmerald)
                        .foregroundStyle(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .shadow(color: theme.accentEmerald.opacity(0.3), radius: 6, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                }
            }

            // MARK: - Live Autocomplete Dropdown
            if isSearchFocused && !searchText.trimmingCharacters(in: .whitespaces).isEmpty && !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("MATCHING PLAYLISTS")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(theme.mutedText)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)

                    ForEach(suggestions.prefix(4)) { item in
                        Button {
                            onSelectSuggestion?(item)
                            searchText = item.name
                            searchFieldFocused = false
                        } label: {
                            HStack(spacing: 10) {
                                AsyncImage(url: URL(string: item.cover_url ?? "")) { phase in
                                    if let img = phase.image {
                                        img.resizable().aspectRatio(contentMode: .fill)
                                    } else {
                                        Rectangle().fill(theme.cardBorder)
                                    }
                                }
                                .frame(width: 28, height: 28)
                                .clipShape(RoundedRectangle(cornerRadius: 6))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(theme.primaryText)
                                        .lineLimit(1)

                                    Text("/playlists/\(item.effectiveFolderSlug) • \(item.effectiveOwner)")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(theme.secondaryText)
                                        .lineLimit(1)
                                }

                                Spacer()

                                Text("\(item.effectiveTotalTracks) tracks")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(theme.accentEmerald)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(theme.pillBackground.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .glassCard(cornerRadius: 12, padding: nil)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // MARK: - Sub-Toolbar
            HStack(spacing: 10) {
                // Left: Count Label
                HStack(spacing: 4) {
                    Text("Showing \(filteredCount)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(theme.primaryText)

                    if filteredCount != totalCount {
                        Text("of \(totalCount)")
                            .font(.caption)
                            .foregroundStyle(theme.mutedText)
                    }

                    Text("playlists")
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                }

                Spacer()

                // Right Controls: Columns Menu (in List View) + Filter Menu + Sort Menu + View Switcher
                HStack(spacing: 6) {
                    // Columns Menu (Visible in List Mode)
                    if viewMode == .list {
                        Menu {
                            Toggle("Cover Art", isOn: $columnConfig.showCover)
                            Toggle("Owner Tag", isOn: $columnConfig.showOwner)
                            Toggle("Track Count", isOn: $columnConfig.showTracks)
                            Toggle("Sync Status", isOn: $columnConfig.showStatus)
                            Toggle("Visibility", isOn: $columnConfig.showVisibility)
                            Toggle("Folder Slug", isOn: $columnConfig.showSlug)
                            Toggle("Action Buttons", isOn: $columnConfig.showActions)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "tablecells")
                                    .font(.system(size: 11))
                                Text("Columns")
                                    .font(.caption2.weight(.semibold))
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(theme.pillBackground)
                            .foregroundStyle(theme.secondaryText)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(theme.cardBorder, lineWidth: 0.8)
                            )
                        }
                    }

                    // Filter Menu
                    Menu {
                        ForEach(FilterOption.allCases) { opt in
                            Button {
                                filterOption = opt
                            } label: {
                                HStack {
                                    Text(opt.rawValue)
                                    if filterOption == opt {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: filterOption.iconName)
                                .font(.system(size: 11))
                            Text(filterOption == .all ? "Filter" : filterOption.rawValue)
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(filterOption != .all ? theme.accentEmeraldGlow : theme.pillBackground)
                        .foregroundStyle(filterOption != .all ? theme.accentEmerald : theme.secondaryText)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(filterOption != .all ? theme.accentEmerald : theme.cardBorder, lineWidth: 0.8)
                        )
                    }

                    // Sort Menu
                    Menu {
                        ForEach(SortOption.allCases) { opt in
                            Button {
                                sortOption = opt
                            } label: {
                                HStack {
                                    Text(opt.rawValue)
                                    if sortOption == opt {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: sortOption.iconName)
                                .font(.system(size: 11))
                            Text("Sort")
                                .font(.caption2.weight(.semibold))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(theme.pillBackground)
                        .foregroundStyle(theme.secondaryText)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(theme.cardBorder, lineWidth: 0.8)
                        )
                    }

                    // Grid vs List View Mode Switcher
                    HStack(spacing: 2) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewMode = .grid
                            }
                        } label: {
                            Image(systemName: "square.grid.2x2")
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(viewMode == .grid ? theme.cardBackground : Color.clear)
                                .foregroundStyle(viewMode == .grid ? theme.primaryText : theme.mutedText)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewMode = .list
                            }
                        } label: {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(viewMode == .list ? theme.cardBackground : Color.clear)
                                .foregroundStyle(viewMode == .list ? theme.primaryText : theme.mutedText)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(2)
                    .background(theme.pillBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(theme.cardBorder, lineWidth: 0.8)
                    )
                }
            }
        }
    }
}
