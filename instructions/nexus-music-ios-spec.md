# 📱 Nexus Music iOS Companion App — Master Technical Specification

## 1. System Overview & User Isolation Model
The **Nexus Music iOS App** (SwiftUI, iOS 17+, Observation framework `@Observable`) is the native mobile controller and streaming player for the self-hosted Nexus Music platform on the **Elysium K3s Cluster** (`atlantis`).

### User Accounts & Isolation
* **Standard Listening Users (`alvish`, `vikas`, `jhansi`)**: Have strict playlist isolation in Navidrome (`is_admin = 0`). They only see playlists they personally requested/imported (`owner_id == user.id`) plus any community playlists marked `public`.
* **Global Admin (`admin`)**: Has superuser visibility across all playlists on the server.
* **Headless Scanner (`nexus_system`)**: Internal service account used by the backend worker to trigger Navidrome library scans.

---

## 2. Network Endpoints & Environments
The app must support switching between **Home Wi-Fi / LAN (Split-DNS)** and **Off-Grid / Tailscale VPN** inside Settings:
* **Sync Engine Base URL**:
  * Primary: `http://sync.nexus.link`
  * Tailscale Fallback: `http://100.110.100.1:80` (with Host header `sync.nexus.link` or configured Ingress)
* **Navidrome Subsonic Base URL**:
  * Primary: `http://navidrome.nexus.link`
  * Tailscale / Direct NodePort Fallback: `http://100.110.100.1:30545`
* **WebSocket Endpoint**:
  * `ws://sync.nexus.link/api/v1/ws?token=<JWT_TOKEN>`

---

## 3. Complete Backend REST API Contract (`sync.nexus.link`)

### A. Authentication (`Bearer <JWT_TOKEN>`)
1. **`POST /api/v1/auth/login`**
   * **Request**: `{"username": "alvish", "password": "..."}`
   * **Response**: `{"access_token": "eyJ...", "token_type": "bearer", "username": "alvish", "is_admin": false, "navidrome_id": "..."}`
   * *Note*: Store `access_token`, `username`, and `password` securely in iOS `Keychain` (the password is used to compute Subsonic MD5 salt+token hashes for direct Navidrome streaming).
2. **`GET /api/v1/auth/me`**
   * **Response**: `{"id": "uuid", "username": "alvish", "is_admin": false}`

### B. Spotify OAuth Session (Optional for Whitelisted Users)
1. **`GET /api/v1/spotify/status`**
   * **Response**: `{"connected": true, "spotify_id": "..."}`
2. **`GET /api/v1/spotify/login`**
   * **Response**: `{"authorization_url": "https://accounts.spotify.com/authorize?..."}`
3. **`POST /api/v1/spotify/disconnect`**
   * **Response**: `{"status": "ok", "message": "Spotify account disconnected successfully."}`
4. **`GET /api/v1/spotify/playlists`**
   * **Response**: Array of `PlaylistItem` objects from the user's connected Spotify account.

### C. Universal Link Ingestion & Public Catalog Search (Zero Whitelist Limit)
1. **`GET /api/v1/playlists/search-public?q=<query>`**
   * Searches Spotify's global catalog using server-side Client Credentials.
   * **Response**:
     ```json
     [
       {
         "id": "37i9dQZF1DXcBWIGoYBM5M",
         "name": "Today's Top Hits",
         "description": "...",
         "cover_url": "[https://i.scdn.co/](https://i.scdn.co/)...",
         "total_tracks": 50,
         "owner_name": "Spotify"
       }
     ]
     ```
2. **`POST /api/v1/playlists/import`**
   * Supports **Dual Import Mode**:
     * **Import Only** (`auto_sync: false`): Registers playlist in `Imported Links` tab in `idle` state without downloading.
     * **Import & Sync** (`auto_sync: true`): Registers playlist and immediately enqueues `spotdl` download job.
   * **Request**:
     ```json
     {
       "url_or_id": "[https://open.spotify.com/playlist/](https://open.spotify.com/playlist/)...",
       "visibility": "private",
       "auto_sync": true
     }
     ```
   * **Response**: `{"status": "ok", "message": "...", "playlist_id": "..."}`
3. **`GET /api/v1/playlists/imported`**
   * Returns all URL-imported playlists for the logged-in user.
4. **`DELETE /api/v1/playlists/{spotify_playlist_id}`**
   * Deletes an imported playlist from PostgreSQL, removes `/mnt/audio_pool/music/playlists/<slug>`, and prunes it from Navidrome.

### D. Playlist Configuration, Sync Trigger & Server Vault
1. **`POST /api/v1/playlists/{spotify_playlist_id}/configure`**
   * Toggles Sync ON/OFF or switches Visibility (`private` vs `public`) in 10ms without moving files on disk.
   * **Request**:
     ```json
     {
       "is_synced": true,
       "visibility": "private",
       "folder_slug": "my_playlist"
     }
     ```
2. **`POST /api/v1/playlists/{spotify_playlist_id}/sync-now`**
   * Enqueues an immediate background sync job in Redis.
3. **`GET /api/v1/playlists/vault`**
   * Returns all playlists stored in the Server Vault, including owner tags.
   * **Response Schema (`PlaylistItem`)**:
     ```json
     {
       "id": "34NpLvuEMI0rv8C9w30wCA",
       "spotify_playlist_id": "34NpLvuEMI0rv8C9w30wCA",
       "name": "bring_this_in",
       "folder_slug": "bring_this_in",
       "visibility": "private",
       "cover_url": "https://...",
       "owner_username": "alvish",
       "is_owner": true,
       "is_synced": true,
       "sync_status": "completed",
       "downloaded_tracks": 12,
       "total_tracks": 12,
       "on_disk_count": 12,
       "folder_path": "/mnt/audio_pool/music/playlists/bring_this_in",
       "last_synced_at": "2026-10-30T10:00:00"
     }
     ```

### E. Real-Time WebSocket Events (`ws://sync.nexus.link/api/v1/ws?token=<JWT>`)
* `TRACK_PROGRESS`: `{"event": "TRACK_PROGRESS", "playlist_id": "...", "folder_slug": "...", "current": 3, "total": 12, "track_title": "...", "downloaded_count": 3}`
* `SYNC_COMPLETED`: `{"event": "SYNC_COMPLETED", "playlist_id": "...", "folder_slug": "...", "downloaded_count": 12, "total_tracks": 12}`
* `PLAYLIST_CONFIGURED` & `PLAYLIST_QUEUED`

---

## 4. Navidrome OpenSubsonic API Contract (`navidrome.nexus.link`)
* **Auth Query Params**: `u=<username>&t=<md5(password+salt)>&s=<random_8_char_salt>&v=1.16.1&c=NexusMusic-iOS&f=json`
* **Endpoints**:
  1. `GET /rest/getPlaylists.view` -> Lists playlists isolated for the logged-in user (`alvish` only sees `alvish`'s private playlists + public playlists).
  2. `GET /rest/getPlaylist.view?id=<playlistId>` -> Returns `entry` array of `SubsonicTrack` items (`id`, `title`, `artist`, `album`, `duration`, `coverArt`, `suffix`, `size`).
  3. `GET /rest/stream.view?id=<trackId>` -> Direct 320kbps MP3 audio stream.
  4. `GET /rest/getCoverArt.view?id=<coverArtId>` -> Album/Playlist artwork image.

---

## 5. Required iOS App UI / UX Architecture (Apple Design Language)
1. **Navigation & Layout**:
   * **iPhone**: Bottom `TabView` with 5 tabs (`Account Sync`, `Imported Links`, `Server Vault`, `Music Player`, `Settings & Links`) plus a floating glassmorphic **MiniPlayer** above the tab bar and a top **Universal Search & Header Bar**.
   * **iPad / Landscape**: Collapsible `NavigationSplitView` sidebar mirroring the web dashboard (`sync.nexus.link`).
2. **Top Header & Sub-Toolbar**:
   * **Top Left**: **Nexus Music** gradient brand title. Tapping it triggers an animated spinning refresh of the active tab.
   * **Top Center/Search**: Search bar with live autocomplete suggestions from local playlists + 1-tap **"Search Spotify Catalog API"** button that opens a global Spotify playlist search & direct import sheet.
   * **Top Right**: Smooth left-to-right **Dark / Bright Theme Toggle Switch** + **+ Import URL** button.
   * **Sub-Toolbar**:
     * **Grid vs. Compact List/Table View Switcher** (works across all tabs including Server Vault).
     * **Sort Menu** (Name A-Z, Name Z-A, Owner A-Z, Most Tracks, Least Tracks) with ascending/descending arrows.
     * **Filter Menu** (All, Synced Only, Unsynced Only, Private Only, Public Only).
3. **Playlist Cards & Table Rows**:
   * Display Cover Art, Title, Folder Slug (`/playlists/<slug>`), and **Owner Badge (`👤 alvish`, `👤 vikas`, `👤 admin`)**.
   * Live WebSocket Progress Bar (`downloaded_tracks / total_tracks` + percentage + current track title when syncing).
   * Controls: **Sync Toggle Switch**, **🔒 Private / 🌍 Public Segmented Pill**, **⚡ Sync Now Bolt Button**, and **🗑️ Delete Button** (for Imported Links).
4. **Dual-Action Import Modal**:
   * Text field for Spotify Playlist URL or ID.
   * Initial Visibility selector (`🔒 Private` vs `🌍 Public`).
   * Two distinct action buttons: **"Import Only"** (`auto_sync: false`) and **"Import & Sync"** (`auto_sync: true`).
5. **Settings, Canvas Customizer & Ecosystem Links**:
   * **Theme & Contrast**: Dark Mode vs. Bright Mode (with high-contrast adaptive text).
   * **Background Canvas**: 12 curated color presets (OLED Black, Dark Slate, Midnight, Emerald, Amethyst, Crimson, Cyan Deep, Rose Quartz, Cloud White, Alabaster, Soft Sage, Lavender), Image URL input, and **native iOS `PhotosPicker`** to set any photo from the user's iPhone library as the app background with glassmorphic blur.
   * **Spotify OAuth Card**: Shows connection status with **Connect / Switch Account** and **Disconnect (Unlink)** buttons.
   * **Ecosystem & Dev Quick Links**: Opens `https://nexus.link/boards/apps-v2`, `http://music.nexus.link` (Feishin), `http://navidrome.nexus.link`, `http://gitops.nexus.link` (ArgoCD), and `https://developer.spotify.com/dashboard`.
6. **Built-in Subsonic Audio Player & Offline Flight Mode**:
   * Plays tracks from Navidrome playlists with queue management (Next, Previous, Shuffle, Repeat).
   * Integrates `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter` for Lock Screen, Control Center, AirPlay, and CarPlay.
   * **1-Tap Offline Caching**: Downloads MP3s to local `Documents/OfflineTracks/` so playlists work in Airplane Mode without network access.
