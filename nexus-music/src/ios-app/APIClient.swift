import Foundation
import Observation
import CryptoKit

public enum APIError: LocalizedError, Sendable {
    case invalidURL(String)
    case invalidResponse
    case httpError(statusCode: Int, payload: String?)
    case unauthorized
    case decodingError(String)
    case networkError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .invalidResponse:
            return "Unexpected response format received from server."
        case .httpError(let statusCode, let payload):
            if let payload = payload, !payload.isEmpty {
                return "Server returned HTTP \(statusCode): \(payload)"
            }
            return "Server returned HTTP error status \(statusCode)."
        case .unauthorized:
            return "Session expired or authentication failed. Please sign in again."
        case .decodingError(let detail):
            return "Failed to decode response: \(detail)"
        case .networkError(let detail):
            return "Network communication error: \(detail)"
        }
    }
}

@Observable
public final class APIClient: @unchecked Sendable {
    public static let shared = APIClient()

    private enum DefaultsKey {
        static let syncBaseURL = "nexus_music_sync_base_url"
        static let navidromeBaseURL = "nexus_music_navidrome_base_url"
    }

    // MARK: - State Properties

    public var isAuthenticated: Bool = false
    public var currentUsername: String = ""
    public var jwtToken: String = ""

    public var subsonicUser: String = ""
    public var subsonicPass: String = ""

    public var syncBaseURL: String {
        didSet {
            UserDefaults.standard.set(syncBaseURL, forKey: DefaultsKey.syncBaseURL)
        }
    }

    public var navidromeBaseURL: String {
        didSet {
            UserDefaults.standard.set(navidromeBaseURL, forKey: DefaultsKey.navidromeBaseURL)
        }
    }

    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30.0
        configuration.timeoutIntervalForResource = 120.0
        self.session = URLSession(configuration: configuration)

        let savedSyncURL = UserDefaults.standard.string(forKey: DefaultsKey.syncBaseURL)
        let savedNavidromeURL = UserDefaults.standard.string(forKey: DefaultsKey.navidromeBaseURL)

        self.syncBaseURL = (savedSyncURL?.isEmpty == false) ? savedSyncURL! : "http://sync.nexus.link"
        self.navidromeBaseURL = (savedNavidromeURL?.isEmpty == false) ? savedNavidromeURL! : "http://navidrome.nexus.link"

        checkExistingLogin()
    }

    // MARK: - Session Bootstrap

    public func checkExistingLogin() {
        if let token = KeychainHelper.shared.read(.jwtToken),
           let user = KeychainHelper.shared.read(.username),
           let pass = KeychainHelper.shared.read(.subsonicPass),
           !token.isEmpty, !user.isEmpty {
            self.jwtToken = token
            self.currentUsername = user
            self.subsonicUser = user
            self.subsonicPass = pass
            self.isAuthenticated = true
            WebSocketManager.shared.connect(token: token)
        } else {
            self.isAuthenticated = false
        }
    }

    // MARK: - Authentication Endpoints

    public func login(username: String, pass: String) async throws -> TokenResponse {
        let cleanedSyncURL = syncBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(cleanedSyncURL)/api/v1/auth/login") else {
            throw APIError.invalidURL("\(cleanedSyncURL)/api/v1/auth/login")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = LoginRequest(username: username, password: pass)
        request.httpBody = try JSONEncoder().encode(payload)

        let tokenRes: TokenResponse = try await execute(request)

        self.jwtToken = tokenRes.access_token
        self.currentUsername = tokenRes.username
        self.subsonicUser = username
        self.subsonicPass = pass
        self.isAuthenticated = true

        KeychainHelper.shared.save(.jwtToken, value: tokenRes.access_token)
        KeychainHelper.shared.save(.username, value: tokenRes.username)
        KeychainHelper.shared.save(.subsonicPass, value: pass)

        WebSocketManager.shared.connect(token: tokenRes.access_token)
        return tokenRes
    }

    public func fetchCurrentUser() async throws -> UserProfile {
        let cleanedSyncURL = syncBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(cleanedSyncURL)/api/v1/auth/me") else {
            throw APIError.invalidURL("\(cleanedSyncURL)/api/v1/auth/me")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        attachAuthHeader(to: &request)

        return try await execute(request)
    }

    public func logout() {
        KeychainHelper.shared.clearAll()
        self.jwtToken = ""
        self.currentUsername = ""
        self.subsonicUser = ""
        self.subsonicPass = ""
        self.isAuthenticated = false
        WebSocketManager.shared.disconnect()
    }

    // MARK: - Spotify OAuth Endpoints

    public func fetchSpotifyStatus() async throws -> SpotifyStatus {
        let cleanedSyncURL = syncBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(cleanedSyncURL)/api/v1/spotify/status") else {
            throw APIError.invalidURL("\(cleanedSyncURL)/api/v1/spotify/status")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        attachAuthHeader(to: &request)

        return try await execute(request)
    }

    public func getSpotifyLoginURL() async throws -> URL {
        let cleanedSyncURL = syncBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(cleanedSyncURL)/api/v1/spotify/login") else {
            throw APIError.invalidURL("\(cleanedSyncURL)/api/v1/spotify/login")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        attachAuthHeader(to: &request)

        let response: SpotifyLoginResponse = try await execute(request)
        guard let parsedURL = URL(string: response.authorization_url) else {
            throw APIError.invalidURL(response.authorization_url)
        }
        return parsedURL
    }

    public func disconnectSpotify() async throws {
        let cleanedSyncURL = syncBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(cleanedSyncURL)/api/v1/spotify/disconnect") else {
            throw APIError.invalidURL("\(cleanedSyncURL)/api/v1/spotify/disconnect")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        attachAuthHeader(to: &request)

        let _: GenericActionResponse = try await execute(request)
    }

    public func fetchSpotifyAccountPlaylists() async throws -> [PlaylistItem] {
        let cleanedSyncURL = syncBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(cleanedSyncURL)/api/v1/spotify/playlists") else {
            throw APIError.invalidURL("\(cleanedSyncURL)/api/v1/spotify/playlists")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        attachAuthHeader(to: &request)

        return try await execute(request)
    }

    // MARK: - Link Ingestion & Public Catalog

    public func fetchImportedPlaylists() async throws -> [PlaylistItem] {
        let cleanedSyncURL = syncBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(cleanedSyncURL)/api/v1/playlists/imported") else {
            throw APIError.invalidURL("\(cleanedSyncURL)/api/v1/playlists/imported")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        attachAuthHeader(to: &request)

        return try await execute(request)
    }

    public func importPlaylist(
        urlOrId: String,
        visibility: String,
        autoSync: Bool
    ) async throws -> PlaylistImportResponse {
        let cleanedSyncURL = syncBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(cleanedSyncURL)/api/v1/playlists/import") else {
            throw APIError.invalidURL("\(cleanedSyncURL)/api/v1/playlists/import")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        attachAuthHeader(to: &request)

        let body = PlaylistImportRequest(url_or_id: urlOrId, visibility: visibility, auto_sync: autoSync)
        request.httpBody = try JSONEncoder().encode(body)

        return try await execute(request)
    }

    public func deleteImportedPlaylist(spotifyId: String) async throws {
        let cleanedSyncURL = syncBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(cleanedSyncURL)/api/v1/playlists/\(spotifyId)") else {
            throw APIError.invalidURL("\(cleanedSyncURL)/api/v1/playlists/\(spotifyId)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        attachAuthHeader(to: &request)

        let _: GenericActionResponse = try await execute(request)
    }

    public func searchPublicSpotifyCatalog(query: String) async throws -> [PublicSpotifyPlaylist] {
        let cleanedSyncURL = syncBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var components = URLComponents(string: "\(cleanedSyncURL)/api/v1/playlists/search-public")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]

        guard let url = components?.url else {
            throw APIError.invalidURL("\(cleanedSyncURL)/api/v1/playlists/search-public?q=\(query)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        attachAuthHeader(to: &request)

        return try await execute(request)
    }

    // MARK: - Playlist Configuration, Sync & Vault

    public func configurePlaylist(
        spotifyId: String,
        isSynced: Bool,
        visibility: String,
        folderSlug: String?
    ) async throws {
        let cleanedSyncURL = syncBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(cleanedSyncURL)/api/v1/playlists/\(spotifyId)/configure") else {
            throw APIError.invalidURL("\(cleanedSyncURL)/api/v1/playlists/\(spotifyId)/configure")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        attachAuthHeader(to: &request)

        let body = PlaylistConfigureRequest(is_synced: isSynced, visibility: visibility, folder_slug: folderSlug)
        request.httpBody = try JSONEncoder().encode(body)

        let _: GenericActionResponse = try await execute(request)
    }

    public func triggerSyncNow(spotifyId: String) async throws {
        let cleanedSyncURL = syncBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(cleanedSyncURL)/api/v1/playlists/\(spotifyId)/sync-now") else {
            throw APIError.invalidURL("\(cleanedSyncURL)/api/v1/playlists/\(spotifyId)/sync-now")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        attachAuthHeader(to: &request)

        let _: GenericActionResponse = try await execute(request)
    }

    public func fetchVaultPlaylists() async throws -> [PlaylistItem] {
        let cleanedSyncURL = syncBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(cleanedSyncURL)/api/v1/playlists/vault") else {
            throw APIError.invalidURL("\(cleanedSyncURL)/api/v1/playlists/vault")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        attachAuthHeader(to: &request)

        return try await execute(request)
    }

    // MARK: - OpenSubsonic & Navidrome Helpers

    public func getSubsonicAuthParams() -> String {
        let salt = String(UUID().uuidString.prefix(8)).lowercased()
        let combined = subsonicPass + salt
        let hashData = Insecure.MD5.hash(data: Data(combined.utf8))
        let token = hashData.map { String(format: "%02hhx", $0) }.joined()

        let encodedUser = subsonicUser.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subsonicUser
        return "u=\(encodedUser)&t=\(token)&s=\(salt)&v=1.16.1&c=NexusMusic-iOS&f=json"
    }

    public func fetchSubsonicPlaylists() async throws -> [SubsonicPlaylist] {
        let cleanedNavidromeURL = navidromeBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let authParams = getSubsonicAuthParams()
        guard let url = URL(string: "\(cleanedNavidromeURL)/rest/getPlaylists.view?\(authParams)") else {
            throw APIError.invalidURL("\(cleanedNavidromeURL)/rest/getPlaylists.view")
        }

        let request = URLRequest(url: url)
        let wrapper: SubsonicWrapper<SubsonicPlaylistsPayload> = try await execute(request)
        return wrapper.subsonicResponse.playlists?.playlist ?? []
    }

    public func fetchSubsonicPlaylistTracks(playlistId: String) async throws -> [SubsonicTrack] {
        let cleanedNavidromeURL = navidromeBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let authParams = getSubsonicAuthParams()
        guard let url = URL(string: "\(cleanedNavidromeURL)/rest/getPlaylist.view?id=\(playlistId)&\(authParams)") else {
            throw APIError.invalidURL("\(cleanedNavidromeURL)/rest/getPlaylist.view")
        }

        let request = URLRequest(url: url)
        let wrapper: SubsonicWrapper<SubsonicPlaylistDetailPayload> = try await execute(request)
        return wrapper.subsonicResponse.playlist?.entry ?? []
    }

    public func getStreamURL(trackId: String) -> URL? {
        let cleanedNavidromeURL = navidromeBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let authParams = getSubsonicAuthParams()
        return URL(string: "\(cleanedNavidromeURL)/rest/stream.view?id=\(trackId)&\(authParams)")
    }

    public func getCoverArtURL(coverId: String?) -> URL? {
        guard let coverId = coverId, !coverId.isEmpty else { return nil }
        let cleanedNavidromeURL = navidromeBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let authParams = getSubsonicAuthParams()
        return URL(string: "\(cleanedNavidromeURL)/rest/getCoverArt.view?id=\(coverId)&\(authParams)")
    }

    // MARK: - Private Pipeline Helpers

    private func attachAuthHeader(to request: inout URLRequest) {
        if !jwtToken.isEmpty {
            request.setValue("Bearer \(jwtToken)", forHTTPHeaderField: "Authorization")
        }
    }

    private func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            logout()
            throw APIError.unauthorized
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8)
            throw APIError.httpError(statusCode: httpResponse.statusCode, payload: errorBody)
        }

        do {
            return try JSONDecoder().decode(T.self, data: data)
        } catch {
            let body = String(data: data, encoding: .utf8) ?? "Unreadable Data"
            throw APIError.decodingError("Error: \(error.localizedDescription) | Raw Body: \(body)")
        }
    }
}
