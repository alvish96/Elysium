import Foundation
import CryptoKit
import Observation

@Observable
public final class APIClient: @unchecked Sendable {
    public static let shared = APIClient()

    public var syncBaseURL: String {
        didSet { UserDefaults.standard.set(syncBaseURL, forKey: "nexus_sync_base_url") }
    }
    public var navidromeBaseURL: String {
        didSet { UserDefaults.standard.set(navidromeBaseURL, forKey: "nexus_navidrome_base_url") }
    }
    public var feishinBaseURL: String {
        didSet { UserDefaults.standard.set(feishinBaseURL, forKey: "nexus_feishin_base_url") }
    }

    public var isAuthenticated: Bool = false
    public var currentUsername: String = "alvish"
    public var spotifyStatus = SpotifyStatus(connected: false, spotify_id: nil, display_name: nil)

    public var spotifyPlaylists: [PlaylistItem] = []
    public var importedPlaylists: [PlaylistItem] = []
    public var vaultPlaylists: [PlaylistItem] = []
    public var deletedPlaylistIDs: Set<String> = []
    public var newlyDiscoveredPlaylistIDs: Set<String> = []
    public var lastDiscoveryBanner: String? = nil

    public var activeStreams: [ActiveDownloadStream] = []
    public var pendingQueue: [PendingQueueJob] = []
    public var pendingCount: Int = 0
    public var completedHistory: [CompletedHistoryItem] = []

    public var downloadedTracks: [DownloadedTrackFile] = []
    public var totalTracksDiskMB: Double = 0.0

    private var telemetryTask: Task<Void, Never>?
    private var rapidPollTicksRemaining: Int = 0

    private init() {
        self.syncBaseURL = UserDefaults.standard.string(forKey: "nexus_sync_base_url") ?? "http://sync.nexus.link"
        self.navidromeBaseURL = UserDefaults.standard.string(forKey: "nexus_navidrome_base_url") ?? "http://navidrome.nexus.link"
        self.feishinBaseURL = UserDefaults.standard.string(forKey: "nexus_feishin_base_url") ?? "http://music.nexus.link"
        if let savedDeleted = UserDefaults.standard.stringArray(forKey: "nexus_deleted_playlists") {
            self.deletedPlaylistIDs = Set(savedDeleted)
        }
        checkExistingSession()
    }

    public var feishinPlayerURL: URL? {
        URL(string: feishinBaseURL.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public func checkExistingSession() {
        if let token = KeychainHelper.shared.read(.jwtToken), !token.isEmpty {
            self.isAuthenticated = true
            self.currentUsername = KeychainHelper.shared.read(.username) ?? "alvish"
            startLiveTelemetryLoop()
            Task { await refreshAllData() }
        } else {
            self.isAuthenticated = false
        }
    }

    private func makeRequest(
        path: String,
        method: String = "GET",
        body: Data? = nil
    ) throws -> URLRequest {
        let base = syncBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)\(path)") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = KeychainHelper.shared.read(.jwtToken), !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = body
        return req
    }

    private func extractServerError(from data: Data, fallback: String) -> String {
        struct ErrBody: Codable { let detail: String?; let message: String? }
        if let decoded = try? JSONDecoder().decode(ErrBody.self, from: data) {
            return decoded.detail ?? decoded.message ?? fallback
        }
        if let raw = String(data: data, encoding: .utf8), !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return String(raw.prefix(160))
        }
        return fallback
    }

    @MainActor
    public func login(username: String, pass: String) async throws {
        let payload = try JSONEncoder().encode(LoginRequest(username: username, password: pass))
        let req = try makeRequest(path: "/api/v1/auth/login", method: "POST", body: payload)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Access Denied: Invalid Credentials"])
        }
        let tokenResp = try JSONDecoder().decode(TokenResponse.self, from: data)
        KeychainHelper.shared.save(.jwtToken, value: tokenResp.access_token)
        KeychainHelper.shared.save(.username, value: username)
        KeychainHelper.shared.save(.subsonicPass, value: pass)

        self.currentUsername = username
        self.isAuthenticated = true
        self.spotifyPlaylists = []
        self.importedPlaylists = []
        self.vaultPlaylists = []
        self.newlyDiscoveredPlaylistIDs = []
        startLiveTelemetryLoop()
        await refreshAllData()
    }

    @MainActor
    public func logout() {
        telemetryTask?.cancel()
        KeychainHelper.shared.clearAll()
        spotifyPlaylists = []
        importedPlaylists = []
        vaultPlaylists = []
        newlyDiscoveredPlaylistIDs = []
        lastDiscoveryBanner = nil
        isAuthenticated = false
    }

    @MainActor
    public func refreshAllData() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fetchCurrentUser() }
            group.addTask { await self.fetchSpotifyStatus() }
            group.addTask { await self.fetchDeletedPlaylistIDs() }
            group.addTask { await self.fetchAllPlaylists() }
            group.addTask { await self.fetchQueueTelemetry() }
            group.addTask { await self.fetchDownloadedTracksArchive() }
        }
    }

    @MainActor
    public func fetchCurrentUser() async {
        guard let req = try? makeRequest(path: "/api/v1/auth/me"),
              let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse else { return }
        if http.statusCode == 401 {
            self.isAuthenticated = false
            return
        }
        if let profile = try? JSONDecoder().decode(UserProfile.self, from: data) {
            self.currentUsername = profile.username
        }
    }

    @MainActor
    public func fetchSpotifyStatus() async {
        guard let req = try? makeRequest(path: "/api/v1/spotify/status"),
              let (data, _) = try? await URLSession.shared.data(for: req),
              let st = try? JSONDecoder().decode(SpotifyStatus.self, from: data) else { return }
        self.spotifyStatus = st
    }

    public func fetchSpotifyOAuthURL() async -> URL? {
        if let req = try? makeRequest(path: "/api/v1/spotify/login?format=json"),
           let (data, resp) = try? await URLSession.shared.data(for: req),
           let http = resp as? HTTPURLResponse, http.statusCode == 200,
           let decoded = try? JSONDecoder().decode(SpotifyAuthURLResponse.self, from: data),
           let target = decoded.resolvedURL,
           let url = URL(string: target) {
            return url
        }
        let base = syncBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let token = KeychainHelper.shared.read(.jwtToken) ?? ""
        return URL(string: "\(base)/api/v1/spotify/login?token=\(token)")
    }

    @MainActor
    public func disconnectSpotify() async {
        guard let req = try? makeRequest(path: "/api/v1/spotify/disconnect", method: "POST") else { return }
        _ = try? await URLSession.shared.data(for: req)
        await refreshAllData()
    }

    @MainActor
    public func transmitCoordinates(urlOrId: String, visibility: String) async throws -> String {
        let trimmed = urlOrId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(domain: "Transmit", code: 400, userInfo: [NSLocalizedDescriptionKey: "Coordinates required"])
        }

        let lower = trimmed.lowercased()
        let isYouTube = lower.contains("youtube.com/") || lower.contains("youtu.be/")
        let isSpotifyTrackOrShort = lower.contains("/track/")
            || lower.contains("spotify:track:")
            || lower.contains("spotify.link/")
            || lower.contains("spoti.fi/")
            || lower.contains("spotify.app.link/")

        if isYouTube || isSpotifyTrackOrShort {
            let body = try JSONEncoder().encode(YouTubeDownloadRequest(url: trimmed, visibility: visibility))
            let req = try makeRequest(path: "/api/v1/downloads/quick", method: "POST", body: body)
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let msg = extractServerError(from: data, fallback: "Download transmission rejected")
                throw NSError(domain: "Transmit", code: (resp as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: msg])
            }
            let decoded = try? JSONDecoder().decode(YouTubeDownloadResponse.self, from: data)
            triggerRapidTelemetryBoost()
            return (decoded?.message ?? "QUEUED FOR IMMEDIATE EXTRACTION").uppercased()
        } else {
            let body = try JSONEncoder().encode(PlaylistImportRequest(url_or_id: trimmed, visibility: visibility, auto_sync: true))
            let req = try makeRequest(path: "/api/v1/playlists/import", method: "POST", body: body)
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let msg = extractServerError(from: data, fallback: "Spotify import rejected")
                throw NSError(domain: "Transmit", code: (resp as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: msg])
            }
            triggerRapidTelemetryBoost()
            await fetchAllPlaylists()
            return "SPOTIFY ARCHIVE IMPORTED & QUEUED"
        }
    }

    public func startLiveTelemetryLoop() {
        telemetryTask?.cancel()
        telemetryTask = Task {
            while !Task.isCancelled {
                await fetchQueueTelemetry()
                let isBusy = !activeStreams.isEmpty || rapidPollTicksRemaining > 0
                if rapidPollTicksRemaining > 0 { rapidPollTicksRemaining -= 1 }
                let sleepNs: UInt64 = isBusy ? 450_000_000 : 2_500_000_000
                try? await Task.sleep(nanoseconds: sleepNs)
            }
        }
    }

    public func triggerRapidTelemetryBoost() {
        rapidPollTicksRemaining = 36
        Task { await fetchQueueTelemetry() }
    }

    @MainActor
    public func fetchQueueTelemetry() async {
        let ts = Int(Date().timeIntervalSince1970 * 1000)
        guard let req = try? makeRequest(path: "/api/v1/downloads/queue?_t=\(ts)"),
              let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let decoded = try? JSONDecoder().decode(QueueTelemetryResponse.self, from: data) else { return }

        self.activeStreams = decoded.active ?? []
        self.pendingQueue = decoded.pending ?? []
        self.pendingCount = decoded.pending_count ?? self.pendingQueue.count
        self.completedHistory = decoded.history ?? []
    }

    @MainActor
    public func cancelOrRemoveDownload(itemID: String) async {
        let encoded = itemID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? itemID
        if let req = try? makeRequest(path: "/api/v1/downloads/queue/\(encoded)", method: "DELETE") {
            _ = try? await URLSession.shared.data(for: req)
        }
        triggerRapidTelemetryBoost()
    }

    @MainActor
    public func clearAllPendingQueue() async -> Int {
        guard let req = try? makeRequest(path: "/api/v1/downloads/queue", method: "DELETE"),
              let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return 0
        }
        let decoded = try? JSONDecoder().decode(ClearQueueResponse.self, from: data)
        self.pendingQueue = []
        self.pendingCount = 0
        triggerRapidTelemetryBoost()
        return decoded?.cleared_count ?? 0
    }

    @MainActor
    public func fetchDeletedPlaylistIDs() async {
        guard let req = try? makeRequest(path: "/api/v1/playlists/deleted"),
              let (data, _) = try? await URLSession.shared.data(for: req),
              let decoded = try? JSONDecoder().decode(DeletedPlaylistsResponse.self, from: data) else { return }
        self.deletedPlaylistIDs = Set(decoded.deleted_ids ?? [])
        UserDefaults.standard.set(Array(self.deletedPlaylistIDs), forKey: "nexus_deleted_playlists")
    }

    @MainActor
    public func fetchAllPlaylists() async {
        async let sp = fetchPlaylistList(endpoint: "/api/v1/spotify/playlists")
        async let imp = fetchPlaylistList(endpoint: "/api/v1/playlists/imported")
        async let vlt = fetchPlaylistList(endpoint: "/api/v1/playlists/vault")

        let (sList, iList, vList) = await (sp, imp, vlt)
        self.spotifyPlaylists = filterDeleted(sList)
        self.importedPlaylists = filterDeleted(iList)
        self.vaultPlaylists = filterDeleted(vList)
    }

    private func filterDeleted(_ items: [PlaylistItem]) -> [PlaylistItem] {
        items.filter { item in
            !deletedPlaylistIDs.contains(item.id) && !deletedPlaylistIDs.contains(item.effectiveSlug)
        }
    }

    private func fetchPlaylistList(endpoint: String) async -> [PlaylistItem] {
        let ts = Int(Date().timeIntervalSince1970 * 1000)
        let sep = endpoint.contains("?") ? "&" : "?"
        guard let req = try? makeRequest(path: "\(endpoint)\(sep)_t=\(ts)"),
              let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return [] }
        if let direct = try? JSONDecoder().decode([PlaylistItem].self, from: data) {
            return direct
        }
        struct Wrapper: Codable { let items: [PlaylistItem]?; let playlists: [PlaylistItem]? }
        if let wrapped = try? JSONDecoder().decode(Wrapper.self, from: data) {
            return wrapped.items ?? wrapped.playlists ?? []
        }
        return []
    }

    @MainActor
    public func configurePlaylist(item: PlaylistItem, isSynced: Bool, visibility: String) async {
        let slug = item.effectiveSlug == "unindexed" ? "" : item.effectiveSlug
        let payload = try? JSONEncoder().encode(
            PlaylistConfigureRequest(is_synced: isSynced, visibility: visibility, folder_slug: slug)
        )
        if let req = try? makeRequest(path: "/api/v1/playlists/\(item.id)/configure", method: "POST", body: payload) {
            _ = try? await URLSession.shared.data(for: req)
        }
        if isSynced {
            await resyncPlaylist(item: item)
        }
        await fetchAllPlaylists()
    }

    @MainActor
    public func forceSyncPlaylist(playlistID: String) async {
        let payload = try? JSONEncoder().encode(PlaylistResyncRequest(name: nil, visibility: nil, folder_slug: nil))
        if let req = try? makeRequest(path: "/api/v1/playlists/\(playlistID)/resync", method: "POST", body: payload) {
            _ = try? await URLSession.shared.data(for: req)
        }
        triggerRapidTelemetryBoost()
    }

    @MainActor
    @discardableResult
    public func resyncPlaylist(item: PlaylistItem) async -> String {
        let slug = item.effectiveSlug == "unindexed" ? nil : item.effectiveSlug
        let body = try? JSONEncoder().encode(
            PlaylistResyncRequest(name: item.displayName, visibility: item.visibility, folder_slug: slug)
        )
        guard let req = try? makeRequest(path: "/api/v1/playlists/\(item.id)/resync", method: "POST", body: body),
              let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return "RE-SYNC FAILED"
        }
        let decoded = try? JSONDecoder().decode(PlaylistResyncResponse.self, from: data)
        triggerRapidTelemetryBoost()
        return (decoded?.message ?? "RE-SYNC STARTED").uppercased()
    }

    @MainActor
    public func resyncAllPlaylists() async throws -> PlaylistResyncAllResponse {
        let body = try JSONEncoder().encode(PlaylistResyncAllRequest(include_unsynced: false))
        let req = try makeRequest(path: "/api/v1/playlists/resync-all", method: "POST", body: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let msg = extractServerError(from: data, fallback: "Re-sync All failed")
            throw NSError(domain: "ResyncAll", code: (resp as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        let decoded = try JSONDecoder().decode(PlaylistResyncAllResponse.self, from: data)
        triggerRapidTelemetryBoost()
        return decoded
    }

    @MainActor
    public func checkNewSpotifyPlaylists() async throws -> CheckNewPlaylistsResponse {
        let knownIDs = spotifyPlaylists.compactMap { $0.effectiveSpotifyID ?? $0.id }
        let body = try JSONEncoder().encode(CheckNewPlaylistsRequest(known_ids: knownIDs))
        let req = try makeRequest(path: "/api/v1/spotify/playlists/check-new", method: "POST", body: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let msg = extractServerError(from: data, fallback: "Spotify playlist check failed")
            throw NSError(domain: "SpotifyCheck", code: (resp as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        let decoded = try JSONDecoder().decode(CheckNewPlaylistsResponse.self, from: data)
        self.newlyDiscoveredPlaylistIDs = Set(decoded.new_ids ?? [])
        self.lastDiscoveryBanner = decoded.message
        await fetchAllPlaylists()
        return decoded
    }

    @MainActor
    public func deletePlaylistFromProfile(item: PlaylistItem) async {
        deletedPlaylistIDs.insert(item.id)
        if item.effectiveSlug != "unindexed" {
            deletedPlaylistIDs.insert(item.effectiveSlug)
        }
        UserDefaults.standard.set(Array(deletedPlaylistIDs), forKey: "nexus_deleted_playlists")
        spotifyPlaylists = filterDeleted(spotifyPlaylists)
        importedPlaylists = filterDeleted(importedPlaylists)
        vaultPlaylists = filterDeleted(vaultPlaylists)

        let slug = item.effectiveSlug == "unindexed" ? "" : item.effectiveSlug
        let offPayload = try? JSONEncoder().encode(
            PlaylistConfigureRequest(is_synced: false, visibility: "private", folder_slug: slug)
        )
        if let req = try? makeRequest(path: "/api/v1/playlists/\(item.id)/configure", method: "POST", body: offPayload) {
            _ = try? await URLSession.shared.data(for: req)
        }
        if let req = try? makeRequest(path: "/api/v1/playlists/imported/\(item.id)", method: "DELETE") {
            _ = try? await URLSession.shared.data(for: req)
        }
        let encodedSlug = slug.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let req = try? makeRequest(path: "/api/v1/playlists/profile/\(item.id)?slug=\(encodedSlug)", method: "DELETE") {
            _ = try? await URLSession.shared.data(for: req)
        }
    }

    @MainActor
    public func restoreHiddenPlaylists() async {
        if let req = try? makeRequest(path: "/api/v1/playlists/deleted/restore", method: "POST") {
            _ = try? await URLSession.shared.data(for: req)
        }
        deletedPlaylistIDs.removeAll()
        UserDefaults.standard.removeObject(forKey: "nexus_deleted_playlists")
        await fetchAllPlaylists()
    }

    @MainActor
    public func fetchDownloadedTracksArchive() async {
        let ts = Int(Date().timeIntervalSince1970 * 1000)
        guard let req = try? makeRequest(path: "/api/v1/downloads/tracks?_t=\(ts)"),
              let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let decoded = try? JSONDecoder().decode(DownloadedTracksEnvelope.self, from: data) else { return }
        self.downloadedTracks = decoded.tracks
        self.totalTracksDiskMB = decoded.total_size_mb
    }

    public func directDownloadedTrackStreamURL(filename: String) -> URL? {
        let base = syncBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let encoded = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? filename
        return URL(string: "\(base)/api/v1/downloads/tracks/stream/\(encoded)")
    }

    private func subsonicQueryItems() -> [URLQueryItem] {
        let user = KeychainHelper.shared.read(.username) ?? "alvish"
        let pass = KeychainHelper.shared.read(.subsonicPass) ?? ""
        let salt = "nexus64"
        let digest = Insecure.MD5.hash(data: Data((pass + salt).utf8))
        let token = digest.map { String(format: "%02hhx", $0) }.joined()

        return [
            URLQueryItem(name: "u", value: user),
            URLQueryItem(name: "t", value: token),
            URLQueryItem(name: "s", value: salt),
            URLQueryItem(name: "v", value: "1.16.1"),
            URLQueryItem(name: "c", value: "NexusGalacticIOS"),
            URLQueryItem(name: "f", value: "json")
        ]
    }

    public func fetchSubsonicPlaylists() async -> [SubsonicPlaylist] {
        let base = navidromeBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard var comps = URLComponents(string: "\(base)/rest/getPlaylists.view") else { return [] }
        comps.queryItems = subsonicQueryItems()
        guard let url = comps.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let decoded = try? JSONDecoder().decode(SubsonicResponseWrapper<SubsonicPlaylistsContainer>.self, from: data) else {
            return []
        }
        return decoded.subsonicResponse.playlists?.playlist ?? []
    }

    public func fetchSubsonicPlaylistTracks(playlistId: String) async -> [SubsonicTrack] {
        let base = navidromeBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard var comps = URLComponents(string: "\(base)/rest/getPlaylist.view") else { return [] }
        var items = subsonicQueryItems()
        items.append(URLQueryItem(name: "id", value: playlistId))
        comps.queryItems = items
        guard let url = comps.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let decoded = try? JSONDecoder().decode(SubsonicResponseWrapper<SubsonicPlaylistDetailContainer>.self, from: data) else {
            return []
        }
        return decoded.subsonicResponse.playlist?.entry ?? []
    }

    public func getSubsonicStreamURL(trackId: String) -> URL? {
        let base = navidromeBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard var comps = URLComponents(string: "\(base)/rest/stream.view") else { return nil }
        var items = subsonicQueryItems()
        items.append(URLQueryItem(name: "id", value: trackId))
        comps.queryItems = items
        return comps.url
    }
}
