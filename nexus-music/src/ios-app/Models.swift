import Foundation

// MARK: - Authentication Models

public struct LoginRequest: Codable, Sendable {
    public let username: String
    public let password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

public struct TokenResponse: Codable, Sendable {
    public let access_token: String
    public let token_type: String
    public let username: String
    public let is_admin: Bool
    public let navidrome_id: String?

    public init(
        access_token: String,
        token_type: String = "bearer",
        username: String,
        is_admin: Bool,
        navidrome_id: String? = nil
    ) {
        self.access_token = access_token
        self.token_type = token_type
        self.username = username
        self.is_admin = is_admin
        self.navidrome_id = navidrome_id
    }
}

public struct UserProfile: Codable, Identifiable, Sendable {
    public let id: String
    public let username: String
    public let is_admin: Bool

    public init(id: String, username: String, is_admin: Bool) {
        self.id = id
        self.username = username
        self.is_admin = is_admin
    }
}

// MARK: - Spotify Models

public struct SpotifyStatus: Codable, Sendable {
    public let connected: Bool
    public let spotify_id: String?

    public init(connected: Bool, spotify_id: String? = nil) {
        self.connected = connected
        self.spotify_id = spotify_id
    }
}

public struct SpotifyLoginResponse: Codable, Sendable {
    public let authorization_url: String

    public init(authorization_url: String) {
        self.authorization_url = authorization_url
    }
}

public struct PublicSpotifyPlaylist: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let description: String?
    public let cover_url: String?
    public let total_tracks: Int?
    public let owner_name: String?

    public init(
        id: String,
        name: String,
        description: String? = nil,
        cover_url: String? = nil,
        total_tracks: Int? = nil,
        owner_name: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.cover_url = cover_url
        self.total_tracks = total_tracks
        self.owner_name = owner_name
    }
}

// MARK: - Unified Playlist Model

public struct PlaylistItem: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public var spotify_playlist_id: String?
    public var name: String
    public var description: String?
    public var folder_slug: String?
    public var visibility: String?            // "private" or "public"
    public var cover_url: String?
    public var owner_username: String?
    public var is_owner: Bool?
    public var is_synced: Bool?
    public var sync_status: String?          // "idle", "queued", "syncing", "completed", "failed"
    public var downloaded_tracks: Int?
    public var total_tracks: Int?
    public var on_disk_count: Int?
    public var folder_path: String?
    public var last_synced_at: String?

    public init(
        id: String,
        spotify_playlist_id: String? = nil,
        name: String,
        description: String? = nil,
        folder_slug: String? = nil,
        visibility: String? = "private",
        cover_url: String? = nil,
        owner_username: String? = nil,
        is_owner: Bool? = true,
        is_synced: Bool? = false,
        sync_status: String? = "idle",
        downloaded_tracks: Int? = 0,
        total_tracks: Int? = 0,
        on_disk_count: Int? = 0,
        folder_path: String? = nil,
        last_synced_at: String? = nil
    ) {
        self.id = id
        self.spotify_playlist_id = spotify_playlist_id
        self.name = name
        self.description = description
        self.folder_slug = folder_slug
        self.visibility = visibility
        self.cover_url = cover_url
        self.owner_username = owner_username
        self.is_owner = is_owner
        self.is_synced = is_synced
        self.sync_status = sync_status
        self.downloaded_tracks = downloaded_tracks
        self.total_tracks = total_tracks
        self.on_disk_count = on_disk_count
        self.folder_path = folder_path
        self.last_synced_at = last_synced_at
    }

    // MARK: - Computed Properties

    public var effectiveSpotifyId: String {
        spotify_playlist_id ?? id
    }

    public var effectiveFolderSlug: String {
        folder_slug ?? id
    }

    public var effectiveOwner: String {
        owner_username ?? "Unknown"
    }

    public var effectiveStatus: String {
        sync_status ?? "idle"
    }

    public var isSyncedBool: Bool {
        is_synced ?? false
    }

    public var isPublic: Bool {
        visibility?.lowercased() == "public"
    }

    public var effectiveTotalTracks: Int {
        total_tracks ?? 0
    }

    public var effectiveDownloadedTracks: Int {
        downloaded_tracks ?? on_disk_count ?? 0
    }

    public var progressFraction: Double {
        let total = effectiveTotalTracks
        guard total > 0 else { return 0.0 }
        let current = effectiveDownloadedTracks
        return min(1.0, max(0.0, Double(current) / Double(total)))
    }
}

// MARK: - API Request & Mutation Payloads

public struct PlaylistConfigureRequest: Codable, Sendable {
    public let is_synced: Bool
    public let visibility: String
    public let folder_slug: String?

    public init(is_synced: Bool, visibility: String, folder_slug: String? = nil) {
        self.is_synced = is_synced
        self.visibility = visibility
        self.folder_slug = folder_slug
    }
}

public struct PlaylistImportRequest: Codable, Sendable {
    public let url_or_id: String
    public let visibility: String
    public let auto_sync: Bool

    public init(url_or_id: String, visibility: String, auto_sync: Bool) {
        self.url_or_id = url_or_id
        self.visibility = visibility
        self.auto_sync = auto_sync
    }
}

public struct PlaylistImportResponse: Codable, Sendable {
    public let status: String
    public let message: String
    public let playlist_id: String?

    public init(status: String, message: String, playlist_id: String? = nil) {
        self.status = status
        self.message = message
        self.playlist_id = playlist_id
    }
}

public struct GenericActionResponse: Codable, Sendable {
    public let status: String
    public let message: String

    public init(status: String, message: String) {
        self.status = status
        self.message = message
    }
}

// MARK: - Real-Time WebSocket Models

public struct WSEvent: Codable, Sendable {
    public let event: String
    public let playlist_id: String?
    public let folder_slug: String?
    public let current: Int?
    public let total: Int?
    public let track_title: String?
    public let downloaded_count: Int?
    public let visibility: String?
    public let is_synced: Bool?
    public let sync_status: String?

    public init(
        event: String,
        playlist_id: String? = nil,
        folder_slug: String? = nil,
        current: Int? = nil,
        total: Int? = nil,
        track_title: String? = nil,
        downloaded_count: Int? = nil,
        visibility: String? = nil,
        is_synced: Bool? = nil,
        sync_status: String? = nil
    ) {
        self.event = event
        self.playlist_id = playlist_id
        self.folder_slug = folder_slug
        self.current = current
        self.total = total
        self.track_title = track_title
        self.downloaded_count = downloaded_count
        self.visibility = visibility
        self.is_synced = is_synced
        self.sync_status = sync_status
    }
}

// MARK: - OpenSubsonic / Navidrome Models

public struct SubsonicWrapper<T: Codable & Sendable>: Codable, Sendable {
    public let subsonicResponse: T

    enum CodingKeys: String, CodingKey {
        case subsonicResponse = "subsonic-response"
    }

    public init(subsonicResponse: T) {
        self.subsonicResponse = subsonicResponse
    }
}

public struct SubsonicPlaylistsPayload: Codable, Sendable {
    public let status: String
    public let playlists: SubsonicPlaylistContainer?

    public init(status: String, playlists: SubsonicPlaylistContainer?) {
        self.status = status
        self.playlists = playlists
    }
}

public struct SubsonicPlaylistContainer: Codable, Sendable {
    public let playlist: [SubsonicPlaylist]?

    public init(playlist: [SubsonicPlaylist]?) {
        self.playlist = playlist
    }
}

public struct SubsonicPlaylist: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let comment: String?
    public let owner: String?
    public let `public`: Bool?
    public let songCount: Int?
    public let duration: Int?
    public let coverArt: String?

    public init(
        id: String,
        name: String,
        comment: String? = nil,
        owner: String? = nil,
        public: Bool? = nil,
        songCount: Int? = nil,
        duration: Int? = nil,
        coverArt: String? = nil
    ) {
        self.id = id
        self.name = name
        self.comment = comment
        self.owner = owner
        self.public = `public`
        self.songCount = songCount
        self.duration = duration
        self.coverArt = coverArt
    }
}

public struct SubsonicPlaylistDetailPayload: Codable, Sendable {
    public let status: String
    public let playlist: SubsonicPlaylistDetail?

    public init(status: String, playlist: SubsonicPlaylistDetail?) {
        self.status = status
        self.playlist = playlist
    }
}

public struct SubsonicPlaylistDetail: Codable, Sendable {
    public let id: String
    public let name: String
    public let comment: String?
    public let entry: [SubsonicTrack]?

    public init(id: String, name: String, comment: String? = nil, entry: [SubsonicTrack]?) {
        self.id = id
        self.name = name
        self.comment = comment
        self.entry = entry
    }
}

public struct SubsonicTrack: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let artist: String?
    public let album: String?
    public let duration: Int?
    public let coverArt: String?
    public let suffix: String?
    public let size: Int?
    public let path: String?

    public init(
        id: String,
        title: String,
        artist: String? = nil,
        album: String? = nil,
        duration: Int? = nil,
        coverArt: String? = nil,
        suffix: String? = nil,
        size: Int? = nil,
        path: String? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.coverArt = coverArt
        self.suffix = suffix
        self.size = size
        self.path = path
    }
}

// MARK: - UI & Navigation Control Enums

public enum SortOption: String, CaseIterable, Identifiable, Sendable {
    case nameAsc = "Name (A-Z)"
    case nameDesc = "Name (Z-A)"
    case ownerAsc = "Owner (A-Z)"
    case tracksDesc = "Most Tracks"
    case tracksAsc = "Least Tracks"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .nameAsc: return "arrow.up.circle"
        case .nameDesc: return "arrow.down.circle"
        case .ownerAsc: return "person.crop.circle"
        case .tracksDesc: return "arrow.down.number"
        case .tracksAsc: return "arrow.up.number"
        }
    }
}

public enum FilterOption: String, CaseIterable, Identifiable, Sendable {
    case all = "All Playlists"
    case synced = "Synced Only"
    case unsynced = "Unsynced Only"
    case privateOnly = "Private Only"
    case publicOnly = "Public Only"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .all: return "line.3.horizontal.decrease.circle"
        case .synced: return "checkmark.circle"
        case .unsynced: return "circle"
        case .privateOnly: return "lock.fill"
        case .publicOnly: return "globe"
        }
    }
}

public enum ViewMode: String, CaseIterable, Identifiable, Sendable {
    case grid = "Grid"
    case list = "List"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .list: return "list.bullet"
        }
    }
}
