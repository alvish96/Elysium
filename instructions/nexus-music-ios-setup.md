# 📱 Nexus Music: iOS Subsonic Client & CarPlay Setup Guide

This guide details how to configure native iOS OpenSubsonic clients (**Amperfy**, **play:Sub**, **flo**) to stream from your self-hosted Navidrome server, cache music for offline playback, enable CarPlay/AirPlay controls, and verify Private vs. Public playlist isolation.

---

## 1. Connection Endpoints & Credentials

| Access Method | Server Address | Port | Authentication |
| :--- | :--- | :--- | :--- |
| **LAN / Home Wi-Fi** | `http://navidrome.nexus.link` | `80` (or NodePort `30545`) | Navidrome Username & Password |
| **Off-Grid (Tailscale VPN)** | `http://100.110.100.1:30545` | `30545` | Navidrome Username & Password |

> **Note on Traefik Bypass:** `navidrome.nexus.link` bypasses Authentik ForwardAuth middleware. Native mobile apps submit Subsonic salt-hashed tokens (`u`, `t`, `s` parameters) directly to the API without browser redirect loops.

---

## 2. Amperfy Configuration (Recommended)

1. **Install Amperfy:** Download **Amperfy** from the iOS App Store.
2. **Add Server Account:**
   * Open Amperfy $\rightarrow$ Settings (Gear icon) $\rightarrow$ **Accounts** $\rightarrow$ **Add Account**.
   * **Server Type:** Subsonic / OpenSubsonic
   * **Server URL:** `http://navidrome.nexus.link` (or `http://100.110.100.1:30545`)
   * **Username:** Your Navidrome username (e.g. `admin` or `jhansi`)
   * **Password:** Your Navidrome password
   * Tap **Connect / Save**.
3. **Audio Quality & Transcoding Settings:**
   * Go to **Settings** $\rightarrow$ **Playback & Streaming**.
   * **Wi-Fi Streaming Quality:** Maximum (Direct Play / 320 kbps MP3).
   * **Cellular Streaming Quality:** Auto or 256 kbps (to conserve mobile data).
   * **Audio Engine:** Enable **Gapless Playback** and **Volume Normalization (ReplayGain)**.
4. **CarPlay & Lock Screen Integration:**
   * Amperfy integrates automatically with Apple CarPlay.
   * Go to **Settings** $\rightarrow$ **CarPlay**:
     * Enable **Show Playlists in CarPlay**.
     * Enable **Show Downloaded Music Only** toggle for offline driving.
   * Lock Screen controls (Album artwork, timeline scrubbing, AirPlay device picker) will function via `MPNowPlayingInfoCenter`.
5. **Offline Flight Mode Caching:**
   * Navigate to any playlist (e.g. `peace` or `bring_this_in`).
   * Tap the **••• (Options)** button at the top right $\rightarrow$ **Download Playlist**.
   * Once cached, switch to the **Downloaded** tab at the bottom to listen without Wi-Fi or cellular service.

---

## 3. Alternative Clients: play:Sub & flo

### play:Sub
* **Server URL:** `http://navidrome.nexus.link`
* **Port:** `80` (HTTP)
* Enable **Cache on Stream** so any song played is stored locally in temporary storage.
* Set **Max Cache Size** to `10 GB` under Settings.

### flo
* Tap **+ Add Server** $\rightarrow$ select **Subsonic**.
* Input `http://navidrome.nexus.link` and your user credentials.
* Flo provides a 1:1 Apple Music aesthetic with instant swipe-to-queue gestures.

---

## 4. Verifying Private vs. Public Playlist Isolation

To confirm that your isolated permissions function correctly:

1. **Log in as `admin` on Amperfy:**
   * Go to **Playlists**: You will see all your private playlists (`bring_this_in`, `peace`) plus any community public playlists (`share_list`).
2. **Log in as a secondary user (e.g. `jhansi`) on a second device or private browser:**
   * Open `http://music.nexus.link` or configure a second account in Amperfy using username `jhansi`.
   * Open **Playlists**:
     * `share_list` (**🌍 Public**) is fully visible and playable.
     * `bring_this_in` (**🔒 Private**) and `peace` (**🔒 Private**) are invisible.
3. **Dynamic Visibility Verification:**
   * Open `http://sync.nexus.link` as `admin`.
   * Toggle `peace` from **🔒 Private** to **🌍 Public**.
   * Pull down to refresh playlists on `jhansi`'s app: `peace` appears immediately.
   * Toggle it back to **🔒 Private**: `peace` disappears from `jhansi`'s device while remaining available for `admin`.
