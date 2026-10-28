import Foundation
import Observation
import CryptoKit

@Observable
final class APIClient {
    static let shared = APIClient()

    var isAuthenticated = false
    var currentUsername: String = ""
    var jwtToken: String = ""

    // Subsonic Credentials
    var subsonicUser: String = ""
    var subsonicPass: String = ""

    // Server Endpoints
    var syncBaseURL = "http://sync.nexus.link"
    var navidromeBaseURL = "http://navidrome.nexus.link"

    private init() {}

    func checkExistingLogin() {
        if let token = KeychainHelper.shared.read(key: "jwt_token"),
           let user = KeychainHelper.shared.read(key: "username"),
           let pass = KeychainHelper.shared.read(key: "subsonic_pass") {
            self.jwtToken = token
            self.currentUsername = user
            self.subsonicUser = user
            self.subsonicPass = pass
            self.isAuthenticated = true
            WebSocketManager.shared.connect(token: token)
        }
    }

    func login(username: String, pass: String) async throws {
        guard let url = URL(string: "\(syncBaseURL)/api/v1/auth/login") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = LoginRequest(username: username, password: pass)
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.userAuthenticationRequired)
        }

        let tokenRes = try JSONDecoder().decode(TokenResponse.self, data: data)

        self.jwtToken = tokenRes.access_token
        self.currentUsername = tokenRes.username
        self.subsonicUser = username
        self.subsonicPass = pass
        self.isAuthenticated = true

        KeychainHelper.shared.save(key: "jwt_token", data: tokenRes.access_token)
        KeychainHelper.shared.save(key: "username", data: username)
        KeychainHelper.shared.save(key: "subsonic_pass", data: pass)

        WebSocketManager.shared.connect(token: tokenRes.access_token)
    }

    func logout() {
        KeychainHelper.shared.delete(key: "jwt_token")
        KeychainHelper.shared.delete(key: "username")
        KeychainHelper.shared.delete(key: "subsonic_pass")
        self.jwtToken = ""
        self.currentUsername = ""
        self.subsonicPass = ""
        self.isAuthenticated = false
        WebSocketManager.shared.disconnect()
    }

    // MARK: - Spotify Sync Methods
    func fetchSpotifyStatus() async throws -> SpotifyStatus {
        let url = URL(string: "\(syncBaseURL)/api/v1/spotify/status")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(jwtToken)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(SpotifyStatus.self, data: data)
    }

    func fetchSpotifyPlaylists() async throws -> [SpotifyPlaylist] {
        let url = URL(string: "\(syncBaseURL)/api/v1/spotify/playlists")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(jwtToken)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode([SpotifyPlaylist].self, data: data)
    }

    func configurePlaylist(spotifyId: String, isSynced: Bool, visibility: String, folderSlug: String?) async throws {
        let url = URL(string: "\(syncBaseURL)/api/v1/playlists/\(spotifyId)/configure")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(jwtToken)", forHTTPHeaderField: "Authorization")

        let payload = PlaylistConfigureRequest(is_synced: isSynced, visibility: visibility, folder_slug: folderSlug)
        req.httpBody = try JSONEncoder().encode(payload)
        let _ = try await URLSession.shared.data(for: req)
    }

    func triggerSyncNow(spotifyId: String) async throws {
        let url = URL(string: "\(syncBaseURL)/api/v1/playlists/\(spotifyId)/sync-now")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(jwtToken)", forHTTPHeaderField: "Authorization")
        let _ = try await URLSession.shared.data(for: req)
    }

    // MARK: - Subsonic Auth Helpers
    func getSubsonicURLParams() -> String {
        let salt = UUID().uuidString.prefix(8).lowercased()
        let token = Insecure.MD5.hash(data: (subsonicPass + salt).data(using: .utf8)!)
            .map { String(format: "%02hhx", $0) }.joined()
        return "u=\(subsonicUser)&t=\(token)&s=\(salt)&v=1.16.1&c=NexusMusic-iOS&f=json"
    }

    func fetchSubsonicPlaylists() async throws -> [SubsonicPlaylist] {
        let url = URL(string: "\(navidromeBaseURL)/rest/getPlaylists.view?\(getSubsonicURLParams())")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let wrapper = try JSONDecoder().decode(SubsonicWrapper<SubsonicPlaylistsPayload>.self, data: data)
        return wrapper.subsonicResponse.playlists?.playlist ?? []
    }

    func fetchSubsonicPlaylistDetail(playlistId: String) async throws -> [SubsonicTrack] {
        let url = URL(string: "\(navidromeBaseURL)/rest/getPlaylist.view?id=\(playlistId)&\(getSubsonicURLParams())")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let wrapper = try JSONDecoder().decode(SubsonicWrapper<SubsonicPlaylistDetailPayload>.self, data: data)
        return wrapper.subsonicResponse.playlist?.entry ?? []
    }

    func getStreamURL(trackId: String) -> URL {
        return URL(string: "\(navidromeBaseURL)/rest/stream.view?id=\(trackId)&\(getSubsonicURLParams())")!
    }

    func getCoverArtURL(coverId: String?) -> URL? {
        guard let coverId = coverId, !coverId.isEmpty else { return nil }
        return URL(string: "\(navidromeBaseURL)/rest/getCoverArt.view?id=\(coverId)&\(getSubsonicURLParams())")
    }
}
