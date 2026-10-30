import SwiftUI
import Observation
import AuthenticationServices
import PhotosUI

// MARK: - Web Authentication Presentation Provider

final class WebAuthPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding, @unchecked Sendable {
    static let shared = WebAuthPresentationContextProvider()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene ?? UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return ASPresentationAnchor()
        }
        return windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first ?? ASPresentationAnchor()
    }
}

// MARK: - Settings & Ecosystem Links View

public struct SettingsAndLinksView: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(APIClient.self) private var apiClient
    @Environment(WebSocketManager.self) private var wsManager

    // Spotify OAuth State
    @State private var spotifyStatus: SpotifyStatus? = nil
    @State private var isCheckingSpotify: Bool = false
    @State private var isSpotifyBusy: Bool = false

    // Appearance State
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var customURLInput: String = ""

    // Editable Server Endpoints
    @State private var syncURLEdit: String = ""
    @State private var navidromeURLEdit: String = ""
    @State private var showSaveEndpointAlert: Bool = false
    @State private var showLogoutConfirmation: Bool = false
    @State private var statusFeedbackMessage: String? = nil

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                AppCanvasBackgroundView()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header Banner
                        headerSection

                        // 1. Spotify OAuth Session Card
                        spotifySessionCard

                        // 2. Theme & Canvas Customizer
                        themeAndCanvasCard

                        // 3. Ecosystem & Developer Quick Links
                        ecosystemLinksCard

                        // 4. Server Endpoints & Tailscale Switcher
                        serverEndpointsCard

                        // 5. User Account & Sign Out Footer
                        userAccountFooter
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Settings & Ecosystem")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                syncURLEdit = apiClient.syncBaseURL
                navidromeURLEdit = apiClient.navidromeBaseURL
                customURLInput = theme.remoteWallpaperURLString
                await checkSpotifyConnection()
            }
            .alert("Confirm Sign Out", isPresented: $showLogoutConfirmation) {
                Button("Sign Out", role: .destructive) {
                    apiClient.logout()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to log out of Nexus Music? Your saved Subsonic session credentials will be cleared.")
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Elysium Platform Settings")
                .font(.title3.weight(.bold))
                .foregroundStyle(theme.primaryText)

            Text("Connected cluster node: Atlantis (K3s v1.36) • OpenSubsonic Engine")
                .font(.caption2.monospaced())
                .foregroundStyle(theme.accentEmerald)
        }
        .padding(.top, 4)
    }

    // MARK: - 1. Spotify OAuth Session Card

    private var spotifySessionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "music.note.tv")
                    .font(.subheadline)
                    .foregroundStyle(theme.accentEmerald)

                Text("SPOTIFY OAUTH SESSION")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(theme.mutedText)

                Spacer()

                if let status = spotifyStatus, status.connected {
                    HStack(spacing: 4) {
                        Circle().fill(theme.accentEmerald).frame(width: 6, height: 6)
                        Text("Connected")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(theme.accentEmerald)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(theme.accentEmeraldGlow)
                    .clipShape(Capsule())
                } else {
                    HStack(spacing: 4) {
                        Circle().fill(Color(hex: "#F59E0B")).frame(width: 6, height: 6)
                        Text("Not Linked")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(hex: "#F59E0B"))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color(hex: "#F59E0B").opacity(0.15))
                    .clipShape(Capsule())
                }
            }

            Text("Connect your personal Spotify account to enable automatic sync for personal playlists. (Imported Links do not require Spotify account linking).")
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
                .lineSpacing(2)

            if let spotId = spotifyStatus?.spotify_id {
                Text("Logged in as Spotify User ID: \(spotId)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(theme.mutedText)
            }

            HStack(spacing: 10) {
                // Connect or Switch Account Button
                Button {
                    connectSpotifyOAuth()
                } label: {
                    HStack(spacing: 6) {
                        if isSpotifyBusy {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text((spotifyStatus?.connected == true) ? "Switch Account" : "Connect Spotify")
                                .fontWeight(.bold)
                        }
                    }
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(theme.accentEmerald)
                    .foregroundStyle(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(isSpotifyBusy)

                // Disconnect Button
                if spotifyStatus?.connected == true {
                    Button {
                        disconnectSpotify()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "link.badge.plus")
                            Text("Unlink")
                                .fontWeight(.semibold)
                        }
                        .font(.caption)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Color(hex: "#F43F5E").opacity(0.15))
                        .foregroundStyle(Color(hex: "#F43F5E"))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color(hex: "#F43F5E").opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isSpotifyBusy)
                }
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 16, padding: nil)
    }

    // MARK: - 2. Theme & Canvas Customizer Card

    private var themeAndCanvasCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "paintbrush.pointed.fill")
                    .font(.subheadline)
                    .foregroundStyle(theme.accentEmerald)

                Text("THEME & CANVAS PERSONALIZATION")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(theme.mutedText)
            }

            // Dark vs Bright Mode High-Contrast Switch
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(theme.isLightMode ? "Bright Light Mode" : "Dark Space Mode")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.primaryText)
                    Text("Adapts high-contrast typography and translucent glass borders")
                        .font(.caption2)
                        .foregroundStyle(theme.mutedText)
                }

                Spacer()

                ThemeSliderSwitch()
            }
            .padding(10)
            .background(theme.inputBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // 12 Presets Swatches Grid
            VStack(alignment: .leading, spacing: 6) {
                Text("CANVAS COLOR PRESETS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.mutedText)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                    ForEach(CanvasPreset.allPresets) { preset in
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                theme.setPreset(preset)
                            }
                        } label: {
                            VStack(spacing: 3) {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(hex: preset.hex))
                                    .frame(height: 34)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(
                                                theme.activePreset.id == preset.id ? theme.accentEmerald : theme.cardBorder,
                                                lineWidth: theme.activePreset.id == preset.id ? 2.5 : 0.8
                                            )
                                    )
                                    .overlay(
                                        Group {
                                            if theme.activePreset.id == preset.id {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundStyle(preset.isLight ? Color.black : Color.white)
                                            }
                                        }
                                    )

                                Text(preset.name)
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundStyle(theme.secondaryText)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider().background(theme.cardBorder)

            // Local Photo Picker & Remote URL
            VStack(alignment: .leading, spacing: 8) {
                Text("CUSTOM WALLPAPER")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.mutedText)

                HStack(spacing: 8) {
                    // Native PhotosPicker
                    PhotosPicker(
                        selection: $selectedPhotoItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        HStack(spacing: 6) {
                            Image(systemName: "photo.on.rectangle.angled")
                            Text("Choose from Library")
                        }
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(theme.pillBackground)
                        .foregroundStyle(theme.primaryText)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(theme.cardBorder, lineWidth: 1)
                        )
                    }
                    .onChange(of: selectedPhotoItem) { _, newItem in
                        Task {
                            await theme.loadSelectedPhoto(item: newItem)
                        }
                    }

                    // Reset Wallpaper Button
                    Button {
                        withAnimation {
                            theme.resetBackground()
                            customURLInput = ""
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset")
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .background(theme.pillBackground)
                        .foregroundStyle(theme.mutedText)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }

                // Remote Image URL Field
                HStack(spacing: 6) {
                    TextField("Or paste remote image URL...", text: $customURLInput)
                        .font(.caption)
                        .foregroundStyle(theme.primaryText)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    Button("Apply") {
                        theme.setRemoteWallpaper(url: customURLInput)
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(theme.accentEmerald)
                    .disabled(customURLInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(theme.inputBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(theme.cardBorder, lineWidth: 0.8)
                )
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 16, padding: nil)
    }

    // MARK: - 3. Ecosystem & Developer Quick Links

    private var ecosystemLinksCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "network")
                    .font(.subheadline)
                    .foregroundStyle(theme.accentEmerald)

                Text("ECOSYSTEM & DEV QUICK LINKS")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(theme.mutedText)
            }

            VStack(spacing: 8) {
                ecosystemLinkRow(
                    title: "Nexus Apps Board",
                    subtitle: "Cluster dashboard & service directory",
                    urlString: "https://nexus.link/boards/apps-v2",
                    icon: "square.grid.3x3.fill",
                    colorHex: "#3B82F6"
                )

                ecosystemLinkRow(
                    title: "Feishin Web Player",
                    subtitle: "Desktop & browser Spotify-clone streaming from Navidrome",
                    urlString: "http://music.nexus.link",
                    icon: "play.circle.fill",
                    colorHex: "#10B981"
                )

                ecosystemLinkRow(
                    title: "Navidrome Subsonic Admin",
                    subtitle: "Transcoder, library scanner, and user ACL console",
                    urlString: "http://navidrome.nexus.link",
                    icon: "server.rack",
                    colorHex: "#8B5CF6"
                )

                ecosystemLinkRow(
                    title: "ArgoCD GitOps Console",
                    subtitle: "Continuous delivery repository for Elysium cluster",
                    urlString: "http://gitops.nexus.link",
                    icon: "arrow.triangle.pull",
                    colorHex: "#F59E0B"
                )

                ecosystemLinkRow(
                    title: "Spotify Developer Dashboard",
                    subtitle: "Manage Client ID, Secret, and OAuth Redirect URIs",
                    urlString: "https://developer.spotify.com/dashboard",
                    icon: "wrench.and.screwdriver.fill",
                    colorHex: "#1DB954"
                )
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 16, padding: nil)
    }

    private func ecosystemLinkRow(
        title: String,
        subtitle: String,
        urlString: String,
        icon: String,
        colorHex: String
    ) -> some View {
        Link(destination: URL(string: urlString)!) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(hex: colorHex).opacity(0.18))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(hex: colorHex))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(theme.primaryText)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.caption2)
                    .foregroundStyle(theme.mutedText)
            }
            .padding(8)
            .background(theme.inputBackground.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - 4. Server Endpoints & Tailscale Switcher

    private var serverEndpointsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.subheadline)
                    .foregroundStyle(theme.accentEmerald)

                Text("NETWORK ENDPOINTS & TAILSCALE")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(theme.mutedText)

                Spacer()

                // WebSocket Status Dot
                HStack(spacing: 4) {
                    Circle()
                        .fill(wsManager.isConnected ? theme.accentEmerald : Color(hex: "#F43F5E"))
                        .frame(width: 6, height: 6)

                    Text(wsManager.isConnected ? "WS Active" : "WS Disconnected")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(wsManager.isConnected ? theme.accentEmerald : Color(hex: "#F43F5E"))
                }
            }

            // Quick Environment Presets
            HStack(spacing: 8) {
                Button {
                    syncURLEdit = "http://sync.nexus.link"
                    navidromeURLEdit = "http://navidrome.nexus.link"
                    saveEndpoints()
                } label: {
                    Text("Home LAN / Split-DNS")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(theme.pillBackground)
                        .foregroundStyle(theme.primaryText)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                Button {
                    syncURLEdit = "http://100.110.100.1:80"
                    navidromeURLEdit = "http://100.110.100.1:30545"
                    saveEndpoints()
                } label: {
                    Text("Tailscale VPN (100.110.100.1)")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(theme.pillBackground)
                        .foregroundStyle(theme.accentEmerald)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("SYNC ENGINE BASE URL")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.mutedText)

                TextField("http://sync.nexus.link", text: $syncURLEdit)
                    .font(.caption.monospaced())
                    .foregroundStyle(theme.primaryText)
                    .padding(8)
                    .background(theme.inputBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("NAVIDROME BASE URL")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.mutedText)

                TextField("http://navidrome.nexus.link", text: $navidromeURLEdit)
                    .font(.caption.monospaced())
                    .foregroundStyle(theme.primaryText)
                    .padding(8)
                    .background(theme.inputBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Button {
                saveEndpoints()
            } label: {
                Text("Save & Reconnect Endpoints")
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(theme.accentEmerald)
                    .foregroundStyle(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .glassCard(cornerRadius: 16, padding: nil)
    }

    // MARK: - 5. User Account & Sign Out Footer

    private var userAccountFooter: some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.title3)
                        .foregroundStyle(theme.accentEmerald)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(apiClient.currentUsername.isEmpty ? "Unknown User" : apiClient.currentUsername)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(theme.primaryText)

                        Text("Authenticated via Navidrome Subsonic Token")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.mutedText)
                    }
                }

                Spacer()
            }
            .padding(12)
            .background(theme.inputBackground.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Button {
                showLogoutConfirmation = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right.square")
                    Text("Sign Out of Nexus Music")
                        .fontWeight(.bold)
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(hex: "#F43F5E").opacity(0.12))
                .foregroundStyle(Color(hex: "#F43F5E"))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color(hex: "#F43F5E").opacity(0.35), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }

    // MARK: - Actions

    private func checkSpotifyConnection() async {
        isCheckingSpotify = true
        if let status = try? await apiClient.fetchSpotifyStatus() {
            await MainActor.run {
                self.spotifyStatus = status
                self.isCheckingSpotify = false
            }
        } else {
            await MainActor.run {
                self.isCheckingSpotify = false
            }
        }
    }

    private func connectSpotifyOAuth() {
        isSpotifyBusy = true
        Task {
            do {
                let authURL = try await apiClient.getSpotifyLoginURL()
                await MainActor.run {
                    let session = ASWebAuthenticationSession(
                        url: authURL,
                        callbackURLScheme: "nexusmusic"
                    ) { _, _ in
                        Task {
                            await checkSpotifyConnection()
                            await MainActor.run {
                                self.isSpotifyBusy = false
                            }
                        }
                    }
                    session.presentationContextProvider = WebAuthPresentationContextProvider.shared
                    session.prefersEphemeralWebBrowserSession = false
                    session.start()
                }
            } catch {
                await MainActor.run {
                    self.isSpotifyBusy = false
                }
            }
        }
    }

    private func disconnectSpotify() {
        isSpotifyBusy = true
        Task {
            try? await apiClient.disconnectSpotify()
            await checkSpotifyConnection()
            await MainActor.run {
                self.isSpotifyBusy = false
            }
        }
    }

    private func saveEndpoints() {
        let cleanedSync = syncURLEdit.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedNavidrome = navidromeURLEdit.trimmingCharacters(in: .whitespacesAndNewlines)

        if !cleanedSync.isEmpty {
            apiClient.syncBaseURL = cleanedSync
        }
        if !cleanedNavidrome.isEmpty {
            apiClient.navidromeBaseURL = cleanedNavidrome
        }

        if !apiClient.jwtToken.isEmpty {
            wsManager.connect(token: apiClient.jwtToken)
        }
    }
}
