import Foundation

// MARK: - Auth Models
struct LoginRequest: Codable {
    let username: String
    let password: String
}

struct TokenResponse: Codable {
    let access_token: String
    let token_type: String
    let username: String
    let is_admin: bool
    let navidrome_id: String?
}

struct UserProfile: Codable, Identifiable {
    let id: String
    let username: String
    let is_admin: Bool
}

// MARK: - Spotify Sync Models
struct SpotifyStatus: Codable {
    let connected: Bool
    let spotify_id: String?
}

struct SpotifyPlaylist: Codable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let cover_url: String?
    let total_tracks: Int
    var is_synced: Bool
    var visibility: String  // "private" or "public"
    let folder_slug: String
    var sync_status: String // "idle", "queued", "syncing", "completed", "failed"
    var downloaded_tracks: Int
    let last_synced_at: String?

    var isPublic: Bool {
        visibility == "public"
    }

    var progressFraction: Double {
        guard total_tracks > 0 else { return 0.0 }
        return min(1.0, Double(downloaded_tracks) / Double(total_tracks))
    }
}

struct PlaylistConfigureRequest: Codable {
    let is_synced: Bool
    let visibility: String
    let folder_slug: String?
}

// MARK: - WebSocket Events
struct WSEvent: Codable {
    let event: String
    let playlist_id: String?
    let folder_slug: String?
    let current: Int?
    let total: Int?
    let track_title: String?
    let downloaded_count: Int?
    let visibility: String?
    let is_synced: Bool?
    let sync_status: String?
}

// MARK: - Subsonic Models (Navidrome API)
struct SubsonicWrapper<T: Codable>: Codable {
    let subsonicResponse: T

    enum CodingKeys: String, CodingKey {
        case subsonicResponse = "subsonic-response"
    }
}

struct SubsonicPlaylistsPayload: Codable {
    let status: String
    let playlists: SubsonicPlaylistContainer?
}

struct SubsonicPlaylistContainer: Codable {
    let playlist: [SubsonicPlaylist]?
}

struct SubsonicPlaylist: Codable, Identifiable {
    let id: String
    let name: String
    let comment: String?
    let songCount: Int
    let duration: Int
    let `public`: Bool?
    let coverArt: String?
}

struct SubsonicPlaylistDetailPayload: Codable {
    let status: String
    let playlist: SubsonicPlaylistDetail?
}

struct SubsonicPlaylistDetail: Codable {
    let id: String
    let name: String
    let entry: [SubsonicTrack]?
}

struct SubsonicTrack: Codable, Identifiable {
    let id: String
    let title: String
    let artist: String?
    let album: String?
    let duration: Int?
    let coverArt: String?
    let path: String?
}
