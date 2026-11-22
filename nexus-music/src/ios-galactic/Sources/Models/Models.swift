import Foundation

public struct LoginRequest: Codable, Sendable {
    public let username: String
    public let password: String
}

public struct TokenResponse: Codable, Sendable {
    public let access_token: String
    public let token_type: String?
    public let username: String?
}

public struct UserProfile: Codable, Sendable {
    public let id: String?
    public let username: String
    public let is_admin: Bool?
}

public struct SpotifyStatus: Codable, Sendable {
    public let connected: Bool
    public let spotify_id: String?
    public let display_name: String?
}

public struct SpotifyAuthURLResponse: Codable, Sendable {
    public let authorization_url: String?
    public let url: String?
    public let auth_url: String?

    public var resolvedURL: String? {
        authorization_url ?? url ?? auth_url
    }
}

public struct YouTubeDownloadRequest: Codable, Sendable {
    public let url: String
    public let visibility: String
}

public struct YouTubeDownloadResponse: Codable, Sendable {
    public let status: String?
    public let type: String?
    public let message: String?
    public let task_id: String?
    public let title: String?
}

public struct PlaylistImportRequest: Codable, Sendable {
    public let url_or_id: String
    public let visibility: String
    public let auto_sync: Bool
}

public struct PlaylistConfigureRequest: Codable, Sendable {
    public let is_synced: Bool
    public let visibility: String
    public let folder_slug: String
}

public struct ClearQueueResponse: Codable, Sendable {
    public let status: String?
    public let cleared_count: Int?
}

public struct PlaylistResyncRequest: Codable, Sendable {
    public let name: String?
    public let visibility: String?
    public let folder_slug: String?
}

public struct PlaylistResyncResponse: Codable, Sendable {
    public let status: String?
    public let task_id: String?
    public let playlist_id: String?
    public let name: String?
    public let message: String?
}

public struct PlaylistResyncAllRequest: Codable, Sendable {
    public let include_unsynced: Bool
}

public struct PlaylistResyncAllResponse: Codable, Sendable {
    public let status: String?
    public let queued_count: Int?
    public let playlists: [String]?
    public let message: String?
}

public struct CheckNewPlaylistsRequest: Codable, Sendable {
    public let known_ids: [String]
}

public struct DiscoveredSpotifyPlaylist: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let total_tracks: Int?
}

public struct CheckNewPlaylistsResponse: Codable, Sendable {
    public let status: String?
    public let total_count: Int?
    public let new_count: Int?
    public let new_ids: [String]?
    public let new_playlists: [DiscoveredSpotifyPlaylist]?
    public let message: String?
}

public struct QueueTelemetryResponse: Codable, Sendable {
    public let active: [ActiveDownloadStream]?
    public let pending: [PendingQueueJob]?
    public let pending_count: Int?
    public let history: [CompletedHistoryItem]?
}

public struct PlaylistTrackProgress: Codable, Identifiable, Hashable, Sendable {
    public var id: Int { index }
    public let index: Int
    public let name: String
    public let status: String // "queued", "downloading", "done", "cached", "failed"
    public let percent: Double
    public let detail: String?
}

public struct ActiveDownloadStream: Codable, Identifiable, Sendable {
    public var id: String { task_id ?? raw_id ?? title ?? UUID().uuidString }
    public let raw_id: String?
    public let task_id: String?
    public let title: String?
    public let artist: String?
    public let percent: Double?
    public let overall_percent: Double?
    public let speed: String?
    public let eta: String?
    public let status: String?
    public let owner: String?
    public let log_line: String?
    public let is_playlist: Bool?
    public let playlist_name: String?
    public let completed_tracks: Int?
    public let total_tracks: Int?
    public let current_index: Int?
    public let current_track: String?
    public let track_percent: Double?
    public let tracks: [PlaylistTrackProgress]?

    enum CodingKeys: String, CodingKey {
        case raw_id = "id"
        case task_id
        case title, artist, percent, overall_percent, speed, eta, status, owner
        case log_line, is_playlist, playlist_name, completed_tracks, total_tracks
        case current_index, current_track, track_percent, tracks
    }

    public var effectiveOverallPercent: Double {
        max(0.0, min(100.0, overall_percent ?? percent ?? 0.0))
    }

    public var isPlaylistStream: Bool {
        (is_playlist == true) || !(tracks ?? []).isEmpty
    }

    public var effectiveLogLine: String {
        if let log = log_line, !log.isEmpty { return log }
        return "\(title ?? "Processing") — \(speed ?? "Live")"
    }
}

public struct PendingQueueJob: Codable, Identifiable, Sendable {
    public var id: String { task_id ?? playlist_id ?? raw_id ?? url ?? UUID().uuidString }
    public let raw_id: String?
    public let task_id: String?
    public let playlist_id: String?
    public let title: String?
    public let name: String?
    public let url: String?
    public let task_type: String?
    public let type: String?
    public let owner: String?
    public let status: String?

    enum CodingKeys: String, CodingKey {
        case raw_id = "id"
        case task_id, playlist_id, title, name, url, task_type, type, owner, status
    }

    public var displayTitle: String {
        let candidate = (title ?? name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !candidate.isEmpty, candidate.lowercased() != "queued track" {
            return candidate
        }
        return url ?? "Queued Track"
    }

    public var effectiveType: String {
        type ?? task_type ?? "track"
    }
}

public struct CompletedHistoryItem: Codable, Identifiable, Sendable {
    public var id: String { raw_id ?? file ?? (title ?? "") + (completed_at ?? "") }
    public let raw_id: String?
    public let title: String?
    public let artist: String?
    public let status: String?
    public let file: String?
    public let completed_at: String?

    enum CodingKeys: String, CodingKey {
        case raw_id = "id"
        case title, artist, status, file, completed_at
    }
}

public struct PlaylistItem: Codable, Identifiable, Hashable, Sendable {
    public var id: String { spotify_id ?? spotify_playlist_id ?? raw_id ?? folder_slug ?? UUID().uuidString }
    public let raw_id: String?
    public let spotify_id: String?
    public let spotify_playlist_id: String?
    public let name: String?
    public let title: String?
    public let cover_url: String?
    public let image_url: String?
    public let owner_username: String?
    public let owner: String?
    public let total_tracks: Int?
    public let tracks_total: Int?
    public let downloaded_tracks: Int?
    public let on_disk_count: Int?
    public var is_synced: Bool?
    public let sync_status: String?
    public var visibility: String?
    public let folder_slug: String?
    public let folder_path: String?

    enum CodingKeys: String, CodingKey {
        case raw_id = "id"
        case spotify_id, spotify_playlist_id, name, title
        case cover_url, image_url, owner_username, owner
        case total_tracks, tracks_total, downloaded_tracks, on_disk_count
        case is_synced, sync_status, visibility, folder_slug, folder_path
    }

    public var displayName: String { name ?? title ?? "UNTITLED ARCHIVE" }
    public var displayCover: String? { cover_url ?? image_url }
    public var displayOwner: String { (owner_username ?? owner ?? "alvish").uppercased() }
    public var effectiveTotal: Int { total_tracks ?? tracks_total ?? 0 }
    public var effectiveDownloaded: Int { downloaded_tracks ?? on_disk_count ?? 0 }
    public var effectiveSlug: String { folder_slug ?? folder_path ?? "unindexed" }
    public var isPublic: Bool { (visibility ?? "private").lowercased() == "public" }
    public var effectiveSynced: Bool { is_synced ?? (sync_status?.lowercased() == "synced") }

    public var effectiveSpotifyID: String? {
        let candidates = [spotify_playlist_id, spotify_id, raw_id].compactMap { $0 }
        return candidates.first { $0.count == 22 && $0.allSatisfy { $0.isLetter || $0.isNumber } }
    }

    public var spotifyWebURL: URL? {
        guard let spId = effectiveSpotifyID else { return nil }
        return URL(string: "https://open.spotify.com/playlist/\(spId)")
    }

    public var progressFraction: Double {
        guard effectiveTotal > 0 else { return 0 }
        return min(1.0, max(0.0, Double(effectiveDownloaded) / Double(effectiveTotal)))
    }

    public var progressPercent: Int {
        Int(round(progressFraction * 100))
    }
}

public struct DeletedPlaylistsResponse: Codable, Sendable {
    public let deleted_ids: [String]?
}

public struct DownloadedTracksEnvelope: Codable, Sendable {
    public let total_count: Int
    public let total_size_mb: Double
    public let tracks: [DownloadedTrackFile]
}

public struct DownloadedTrackFile: Codable, Identifiable, Hashable, Sendable {
    public var id: String { filename }
    public let filename: String
    public let title: String
    public let artist: String
    public let size_mb: Double
    public let modified_at: Double
}

public struct SubsonicResponseWrapper<T: Codable>: Codable {
    public let subsonicResponse: T

    enum CodingKeys: String, CodingKey {
        case subsonicResponse = "subsonic-response"
    }
}

public struct SubsonicPlaylistsContainer: Codable {
    public let status: String
    public let playlists: SubsonicPlaylistsList?
}

public struct SubsonicPlaylistsList: Codable {
    public let playlist: [SubsonicPlaylist]?
}

public struct SubsonicPlaylist: Codable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let songCount: Int?
    public let duration: Int?
    public let owner: String?
    public let `public`: Bool?
}

public struct SubsonicPlaylistDetailContainer: Codable {
    public let status: String
    public let playlist: SubsonicPlaylistWithTracks?
}

public struct SubsonicPlaylistWithTracks: Codable {
    public let id: String
    public let name: String
    public let entry: [SubsonicTrack]?
}

public struct SubsonicTrack: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let artist: String?
    public let album: String?
    public let duration: Int?
    public let coverArt: String?
    public let suffix: String?
    public var directStreamURL: URL?
}

public enum ArchiveSource: String, CaseIterable {
    case spotify = "SPOTIFY ACCOUNT"
    case imported = "IMPORTED LINKS"
    case vault = "SERVER VAULT"
}

public enum ArchiveFilter: String, CaseIterable {
    case all = "ALL"
    case synced = "SYNCED ON"
    case unsynced = "SYNCED OFF"
    case publicOnly = "PUBLIC"
    case privateOnly = "PRIVATE"
}
