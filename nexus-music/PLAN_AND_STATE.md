# 🎵 Nexus Music: Architecture Blueprint & Live Task Tracker

> **Architecture Mode:** Option A — Navidrome-Powered Subsonic Core + Feishin (Spotify Web Player) + Nexus Sync Engine (Multi-User Spotify OAuth, Atomic Hardlink Master Pool, Private/Public Folder Isolation) + iOS Client Suite.

---

## 1. System Architecture & Domain Matrix

| Component | Role | Domain / Ingress | Internal Service | Storage / State Path on `atlantis` |
| :--- | :--- | :--- | :--- | :--- |
| **Navidrome** | Core Audio Streaming & Subsonic API Engine | `navidrome.nexus.link` | `navidrome-svc.media:4533` (NodePort `30545`) | `/mnt/internal/appdata/navidrome` |
| **Feishin** | 1:1 Spotify-Clone Web UI Player | `music.nexus.link` | `feishin-svc.media:9180` | Stateless (Connects to Navidrome) |
| **Nexus Sync API** | FastAPI Backend (Spotify OAuth, Navidrome Auth Bridge, ACLs, WebSockets) | `sync.nexus.link/api` | `nexus-sync-api-svc.media:8000` | `/mnt/internal/appdata/nexus-sync/postgres` |
| **Nexus Sync Worker**| Redis + `spotdl` Downloader, Atomic Hardlinker & `.m3u8` Generator | Internal Worker | `nexus-sync-redis-svc.media:6379` | `/mnt/audio_pool/music` |
| **Nexus Sync WebUI** | Playlist Selector Dashboard (Sync ON/OFF, Private/Public Toggle, Live Logs) | `sync.nexus.link` | `nexus-sync-web-svc.media:3000` | Stateless SPA |
| **iOS Playback & Sync**| Native iPhone Playback (Amperfy/Subsonic) + Native SwiftUI Sync Companion | Tailscale / LAN | Connects to `navidrome.nexus.link` & `sync.nexus.link` | iOS Keychain + Offline Cache |

---

## 2. Storage & Atomic Hardlink Topology (`/mnt/audio_pool/music`)

Because `/mnt/audio_pool` is a MergerFS pool supporting hardlinks (`use_ino`), every song is downloaded **only once** into `.master_pool/` and atomically hardlinked (`os.link`) into each playlist's dedicated folder:

```text
/mnt/audio_pool/music/
├── .master_pool/                                    # Canonical deduplicated 320kbps MP3s (by Spotify Track ID)
│   └── 4cOdK2wGLETKBW3PvgPWqT.mp3
├── public/                                          # 🌍 PUBLIC PLAYLISTS (Visible to ALL users in Navidrome/Feishin/iOS)
│   └── <playlist_folder_slug>/
│       ├── Artist - Title.mp3                       # Hardlinked from .master_pool (0 extra bytes)
│       └── <playlist_folder_slug>.m3u8              # Auto-imported by Navidrome with public=true
└── users/                                           # 🔒 PRIVATE PLAYLISTS (Visible ONLY to the owner)
    └── <navidrome_username>/
        └── private/
            └── <playlist_folder_slug>/
                ├── Artist - Title.mp3               # Hardlinked from .master_pool (0 extra bytes)
                └── <playlist_folder_slug>.m3u8      # Auto-imported by Navidrome with public=false (owner-only)
## 3. Cluster Compliance Rules (Elysium K3s v1.36.2+k3s1)
GitOps Separation: Raw K8s YAML in ~/Elysium/app-code/<app>/; ArgoCD wrappers in ~/Elysium/argocd-apps/<app>-app.yaml.

Secret Isolation: Spotify Client ID/Secret, JWT Secret, and Fernet Key stored in ~/Elysium-essentials/nexus-music-secrets.yaml (never committed to Git).

Pod Security Context: All pods require seccompProfile: {type: Unconfined} and appArmorProfile: {type: Unconfined}.

DNS Resolution: All pods require dnsConfig with ndots: "1".

Ingress Bypass for Mobile Clients: navidrome.nexus.link and sync.nexus.link must NOT use Authentik ForwardAuth middleware so iOS native apps and Subsonic clients can authenticate directly via API tokens.

Deletion Protection: Removing a track on Spotify never deletes an already-downloaded track from .master_pool or the user's folder.

## 4. Master Implementation Checklist
🟢 Phase 0: Project Workspace & Storage Initialization
[x] Task 0.1: Create ~/Elysium/nexus-music/ project tracking directory and PLAN_AND_STATE.md.

[x] Task 0.2: Create /mnt/audio_pool/music/{.master_pool,public,users} and /mnt/internal/appdata/{navidrome,nexus-sync} on atlantis.

[ ] Task 0.3: Create out-of-tree secret manifest ~/Elysium-essentials/nexus-music-secrets.yaml and apply to media namespace.

🟡 Phase 1: Playback Core — Navidrome Upgrade & Feishin (Spotify Web UI)
[ ] Task 1.1: Deploy/Update app-code/navidrome/ pinned to atlantis with /mnt/audio_pool/music mount, .m3u8 auto-import (ND_AUTOIMPORTPLAYLISTS=true), and ND_DEFAULTPLAYLISTPUBLIC=false.

[ ] Task 1.2: Configure navidrome.nexus.link Traefik IngressRoute (bypassing Authentik ForwardAuth for mobile Subsonic compatibility).

[ ] Task 1.3: Deploy app-code/feishin/ (ghcr.io/jeffvli/feishin:latest) pre-wired to navidrome.nexus.link and expose at music.nexus.link.

[ ] Task 1.4: Create ArgoCD wrappers (navidrome-app.yaml, feishin-app.yaml) and verify login on both navidrome.nexus.link and music.nexus.link + iOS Amperfy app.

🟡 Phase 2: Nexus Sync Backend — FastAPI, Postgres, Navidrome Auth & Spotify OAuth
[ ] Task 2.1: Deploy PostgreSQL 16 and Redis 7 manifests in app-code/nexus-sync/postgres-redis.yaml pinned to /mnt/internal/appdata/nexus-sync/ on atlantis.

[ ] Task 2.2: Build FastAPI Backend (models.py, schemas.py, navidrome_bridge.py) authenticating users against Navidrome's /auth/login API and auto-provisioning /mnt/audio_pool/music/users/<username>/private/.

[ ] Task 2.3: Build Spotify OAuth2 service (spotify_service.py) with Fernet encrypted refresh tokens in Postgres and endpoint GET /api/v1/spotify/playlists.

[ ] Task 2.4: Build Playlist Configuration & Atomic Hardlink Visibility Switcher (POST /api/v1/playlists/{id}/configure) + Real-Time WebSocket Hub (/api/v1/ws).

🟡 Phase 3: Smart Download Worker — spotdl, Master Pool Hardlinker & Navidrome Sync
[ ] Task 3.1: Build Redis Worker (worker.py) that downloads missing tracks to /mnt/audio_pool/music/.master_pool/{spotify_track_id}.mp3 with distributed Redis locking.

[ ] Task 3.2: Implement atomic hardlinking (os.link) into /public/<folder>/ or /users/<user>/private/<folder>/ + relative .m3u8 file generation.

[ ] Task 3.3: Implement automatic Navidrome library rescan (/rest/startScan), playlist ownership/visibility sync (public=true|false in Navidrome), and Apprise Discord notifications.

[ ] Task 3.4: Configure 2-hour background scheduler inside the worker to auto-sync newly added songs across all active playlists.

🟡 Phase 4: Nexus Sync Web Dashboard (sync.nexus.link)
[ ] Task 4.1: Build clean dark-mode Web UI (sync.nexus.link) with Navidrome Login, "Connect Spotify" OAuth button, and "Open Web Player (music.nexus.link)" shortcut.

[ ] Task 4.2: Build interactive Playlist Manager table (Sync ON/OFF toggle, 🔒 Private vs 🌍 Public pill switch, live WebSocket progress bars, and manual "Resync Now" button).

[ ] Task 4.3: Containerize and deploy nexus-sync stack (backend, worker, webui, ingress) via ArgoCD (argocd-apps/nexus-sync-app.yaml).

🟡 Phase 5: iOS Ecosystem — Native Sync Companion App & Subsonic Playback
[ ] Task 5.1: Connect iOS Subsonic player (Amperfy / play:Sub) to https://navidrome.nexus.link and verify Private vs. Public playlist visibility, CarPlay, and offline caching.

[ ] Task 5.2: Build Native iOS SwiftUI Companion App ("Nexus Music") connected to sync.nexus.link (REST + WebSockets) and navidrome.nexus.link for unified mobile playlist syncing and playback.

## 5. Progress Changelog
2026-10-27: Initialized ~/Elysium/nexus-music/ workspace, physical storage directories on atlantis, and master PLAN_AND_STATE.md tracker.
