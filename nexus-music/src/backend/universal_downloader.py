import asyncio
import contextvars
import json
import logging
import os
import re
import shutil
import time
from datetime import datetime, timezone
from pathlib import Path
import httpx

logger = logging.getLogger("worker")

TRACKS_DIR = Path("/mnt/audio_pool/music/tracks")
PLAYLISTS_DIR = Path("/mnt/audio_pool/music/playlists")

PCT_RE = re.compile(r"\[download\]\s+(\d+\.?\d*)%")
SPD_RE = re.compile(r"at\s+([0-9.]+[A-Za-z]+/s)")
ETA_RE = re.compile(r"ETA\s+([0-9:]+)")
ITEM_RE = re.compile(r"\[download\]\s+Downloading item\s+(\d+)\s+of\s+(\d+)")
DEST_RE = re.compile(r"\[download\]\s+Destination:\s+(.+)")
INFO_RE = re.compile(r"\[info\]\s+Writing video metadata as JSON to:\s+(.+)")

BROWSER_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"
    )
}

ACTIVE_TRACK_TRACKER: contextvars.ContextVar = contextvars.ContextVar("ACTIVE_TRACK_TRACKER", default=None)


def get_yt_bin() -> str:
    venv_bin = "/opt/worker-venv/bin/yt-dlp"
    return venv_bin if Path(venv_bin).exists() else "yt-dlp"


def sanitize_filename(name: str) -> str:
    cleaned = "".join(c for c in str(name) if c.isalnum() or c in " ._-()&'")
    return re.sub(r"\s+", " ", cleaned).strip() or "Untitled"


def slugify(name: str, fallback: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")
    return slug or fallback


def clean_search_terms(artist: str, title: str) -> tuple[str, str]:
    primary_artist = re.split(r",|&|\bfeat\.?\b|\bft\.?\b", str(artist), flags=re.IGNORECASE)[0].strip()
    clean_title = re.sub(r"\([^)]*\)|\[[^\]]*\]", " ", str(title))
    clean_title = re.sub(
        r"\s+-\s+(from|remaster|version|radio edit|live|acoustic|bonus).*$",
        "",
        clean_title,
        flags=re.IGNORECASE,
    )
    clean_title = re.sub(r"\s+", " ", clean_title).strip()
    return (primary_artist or str(artist).strip()), (clean_title or str(title).strip())


async def is_cancelled(r, task_id: str) -> bool:
    try:
        return bool(await r.sismember("nexus:downloads:cancelled", task_id))
    except Exception:
        return False


async def record_history(r, task_id: str, title: str, artist: str, status: str, file_name: str = ""):
    entry = {
        "id": task_id,
        "title": title,
        "artist": artist,
        "status": status,
        "file": file_name,
        "completed_at": datetime.now(timezone.utc).isoformat(),
    }
    await r.lpush("nexus:downloads:history", json.dumps(entry))
    await r.ltrim("nexus:downloads:history", 0, 49)


async def push_progress(
    r,
    task_id: str,
    title: str,
    artist: str,
    pct: float,
    speed: str,
    eta: str,
    owner: str,
    status: str = "downloading",
    log_line: str = "",
    extra: dict | None = None,
):
    payload = {
        "id": task_id,
        "title": title,
        "artist": artist,
        "percent": round(max(0.0, min(100.0, pct)), 1),
        "overall_percent": round(max(0.0, min(100.0, pct)), 1),
        "speed": speed,
        "eta": eta,
        "status": status,
        "owner": owner,
        "log_line": log_line or f"{title} — {speed}",
    }
    if extra:
        payload.update(extra)
    await r.hset("nexus:downloads:active", task_id, json.dumps(payload))
    await r.publish("nexus:events", json.dumps({"event": "TRACK_PROGRESS", "data": payload}))


class PlaylistTelemetryTracker:
    """Tracks overall playlist %, per-song %, and single-line live status messages in Redis."""

    def __init__(self, r, task_id: str, playlist_name: str, source_label: str, owner: str, track_names: list[str]):
        self.r = r
        self.task_id = str(task_id)
        self.playlist_name = playlist_name
        self.source_label = source_label
        self.owner = owner
        self.current_index = 0
        self.speed = "Live Sync"
        self.eta = "--:--"
        self.log_line = f"Loaded {len(track_names)} tracks for '{playlist_name}' — starting ingestion..."
        self._last_emit = 0.0
        self.tracks = [
            {
                "index": i + 1,
                "name": name,
                "status": "queued",
                "percent": 0.0,
                "detail": "Queued",
            }
            for i, name in enumerate(track_names)
        ]

    @property
    def total(self) -> int:
        return max(len(self.tracks), 1)

    def _compute_overall(self) -> float:
        if not self.tracks:
            return 5.0
        total_pct = sum(float(t.get("percent", 0.0)) for t in self.tracks)
        return round(max(0.0, min(100.0, total_pct / len(self.tracks))), 1)

    def _completed_count(self) -> int:
        return sum(1 for t in self.tracks if t.get("status") in ("done", "cached"))

    async def emit(self, force: bool = False):
        now = time.monotonic()
        if not force and (now - self._last_emit) < 0.25:
            return
        self._last_emit = now

        overall = self._compute_overall()
        done_cnt = self._completed_count()
        cur = self.tracks[self.current_index] if 0 <= self.current_index < len(self.tracks) else None
        cur_name = cur["name"] if cur else self.playlist_name
        cur_pct = float(cur["percent"]) if cur else overall

        await push_progress(
            self.r,
            self.task_id,
            title=f"{self.playlist_name} [{done_cnt}/{len(self.tracks)}]",
            artist=self.source_label,
            pct=overall,
            speed=self.speed,
            eta=self.eta,
            owner=self.owner,
            status="downloading",
            log_line=self.log_line,
            extra={
                "is_playlist": True,
                "playlist_name": self.playlist_name,
                "completed_tracks": done_cnt,
                "total_tracks": len(self.tracks),
                "current_index": (self.current_index + 1) if cur else 0,
                "current_track": cur_name,
                "track_percent": round(cur_pct, 1),
                "tracks": self.tracks,
            },
        )

    async def start_track(self, zero_idx: int, log_line: str = ""):
        if 0 <= zero_idx < len(self.tracks):
            self.current_index = zero_idx
            t = self.tracks[zero_idx]
            t["status"] = "downloading"
            t["percent"] = max(float(t.get("percent", 0.0)), 4.0)
            t["detail"] = "Searching..."
            self.speed = "Matching"
            self.eta = "--:--"
            self.log_line = log_line or f"[{zero_idx + 1}/{len(self.tracks)}] Starting: {t['name']}"
            await self.emit(force=True)

    async def update_track(self, zero_idx: int, pct: float, speed: str = "", eta: str = "", detail: str = "", log_line: str = ""):
        if 0 <= zero_idx < len(self.tracks):
            self.current_index = zero_idx
            t = self.tracks[zero_idx]
            t["status"] = "downloading"
            t["percent"] = round(max(0.0, min(99.0, pct)), 1)
            if detail:
                t["detail"] = detail
            elif speed:
                t["detail"] = speed
            if speed:
                self.speed = speed
            if eta:
                self.eta = eta
            if log_line:
                self.log_line = log_line
            await self.emit(force=False)

    async def mark_cached(self, zero_idx: int):
        if 0 <= zero_idx < len(self.tracks):
            self.current_index = zero_idx
            t = self.tracks[zero_idx]
            t["status"] = "cached"
            t["percent"] = 100.0
            t["detail"] = "In Pool"
            self.speed = "Hardlink"
            self.eta = "00:00"
            self.log_line = f"[{zero_idx + 1}/{len(self.tracks)}] Cached in master pool — linking {t['name']}"
            await self.emit(force=True)

    async def mark_done(self, zero_idx: int, detail: str = "320kbps MP3"):
        if 0 <= zero_idx < len(self.tracks):
            self.current_index = zero_idx
            t = self.tracks[zero_idx]
            t["status"] = "done"
            t["percent"] = 100.0
            t["detail"] = detail
            self.speed = "Saved"
            self.eta = "00:00"
            self.log_line = f"[{zero_idx + 1}/{len(self.tracks)}] Completed: {t['name']} ({detail})"
            await self.emit(force=True)

    async def mark_failed(self, zero_idx: int, reason: str = "Unavailable"):
        if 0 <= zero_idx < len(self.tracks):
            self.current_index = zero_idx
            t = self.tracks[zero_idx]
            t["status"] = "failed"
            t["percent"] = 0.0
            t["detail"] = "Failed"
            self.log_line = f"[{zero_idx + 1}/{len(self.tracks)}] Skipped {t['name']}: {reason[:90]}"
            await self.emit(force=True)

    async def set_log(self, message: str, speed: str = "", force: bool = True):
        self.log_line = message
        if speed:
            self.speed = speed
        await self.emit(force=force)


# ============================================================
# SPOTIFY URL NORMALIZER & 3-TIER TRACK METADATA RESOLVER
# ============================================================
SPOTIFY_TRACK_RE = re.compile(r"(?:open\.spotify\.com/(?:intl-[a-z]{2,3}/)?track/|spotify:track:)([A-Za-z0-9]{22})")
SPOTIFY_PLAYLIST_RE = re.compile(r"(?:open\.spotify\.com/(?:intl-[a-z]{2,3}/)?playlist/|spotify:playlist:)([A-Za-z0-9]{22})")


async def resolve_spotify_url(url: str) -> str:
    """Expands spotify.link / spoti.fi short share links to canonical open.spotify.com URLs."""
    u = str(url or "").strip()
    if any(host in u.lower() for host in ("spotify.link/", "spoti.fi/", "spotify.app.link/")):
        try:
            async with httpx.AsyncClient(timeout=10.0, follow_redirects=True, headers=BROWSER_HEADERS) as client:
                resp = await client.get(u)
                return str(resp.url)
        except Exception as e:
            logger.warning(f"[Universal] Short URL redirect failed for {u}: {e}")
    return u


async def _get_spotify_client_token() -> str | None:
    """Gets an app-level Spotify Client Credentials token (no 5-user OAuth restriction)."""
    cid = os.getenv("SPOTIFY_CLIENT_ID", "").strip()
    csec = os.getenv("SPOTIFY_CLIENT_SECRET", "").strip()
    if not cid or not csec:
        try:
            from config import settings
            cid = cid or getattr(settings, "SPOTIFY_CLIENT_ID", "")
            csec = csec or getattr(settings, "SPOTIFY_CLIENT_SECRET", "")
        except Exception:
            pass
    if not cid or not csec:
        return None
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.post(
                "https://accounts.spotify.com/api/token",
                data={"grant_type": "client_credentials"},
                auth=(cid, csec),
            )
            if resp.status_code == 200:
                return resp.json().get("access_token")
    except Exception as e:
        logger.warning(f"[Universal] Client Credentials token fetch failed: {e}")
    return None


async def resolve_spotify_track_metadata(track_id: str) -> tuple[str, str]:
    """3-tier metadata resolver: 1) Spotify Client Credentials API, 2) Embed JSON, 3) oEmbed + OG meta."""
    # Tier 1: Spotify Web API via Client Credentials (/v1/tracks/{id})
    token = await _get_spotify_client_token()
    if token:
        try:
            async with httpx.AsyncClient(timeout=12.0) as client:
                resp = await client.get(
                    f"https://api.spotify.com/v1/tracks/{track_id}",
                    headers={"Authorization": f"Bearer {token}"},
                )
                if resp.status_code == 200:
                    d = resp.json()
                    title = str(d.get("name") or "").strip()
                    artists = ", ".join(a.get("name", "") for a in (d.get("artists") or []) if a.get("name")).strip()
                    if title:
                        return (artists or "Spotify"), title
        except Exception as e:
            logger.warning(f"[Universal] Spotify API track lookup failed for {track_id}: {e}")

    # Tier 2: Spotify public Embed __NEXT_DATA__ JSON
    try:
        entity = await fetch_spotify_embed_entity("track", track_id)
        title = str(entity.get("name") or entity.get("title") or "").strip()
        artists_list = [a.get("name", "") for a in (entity.get("artists") or []) if a.get("name")]
        artist = ", ".join(artists_list).strip() or str(entity.get("subtitle") or "").strip()
        if title:
            return (artist or "Spotify"), title
    except Exception as e:
        logger.warning(f"[Universal] Spotify embed lookup failed for {track_id}: {e}")

    # Tier 3: Spotify oEmbed + OpenGraph HTML tags
    try:
        track_url = f"https://open.spotify.com/track/{track_id}"
        async with httpx.AsyncClient(timeout=12.0, follow_redirects=True, headers=BROWSER_HEADERS) as client:
            title, artist = "", ""
            oe = await client.get("https://open.spotify.com/oembed", params={"url": track_url})
            if oe.status_code == 200:
                title = str(oe.json().get("title") or "").strip()
            page = await client.get(track_url)
            if page.status_code == 200:
                m_t = re.search(r'<meta[^>]+property="og:title"[^>]+content="([^"]+)"', page.text)
                m_d = re.search(r'<meta[^>]+property="og:description"[^>]+content="([^"]+)"', page.text)
                if not title and m_t:
                    title = m_t.group(1).strip()
                if m_d:
                    # Spotify og:description format: "Artist · Song · Year"
                    parts = [p.strip() for p in re.split(r"·|•", m_d.group(1)) if p.strip()]
                    if parts:
                        artist = parts[0]
            if title:
                return (artist or "Spotify"), title
    except Exception as e:
        logger.warning(f"[Universal] Spotify oEmbed/OG lookup failed for {track_id}: {e}")

    raise ValueError(f"Could not resolve Spotify track metadata for ID {track_id}")


async def trigger_navidrome_quick_scan():
    """Notifies Navidrome to index newly downloaded single tracks immediately."""
    try:
        import hashlib, secrets
        nav_url = os.getenv("NAVIDROME_URL", "http://navidrome-svc.media.svc.cluster.local:4533").rstrip("/")
        nav_user = os.getenv("NAVIDROME_ADMIN_USER", "nexus_system")
        nav_pass = os.getenv("NAVIDROME_ADMIN_PASS", "")
        if not nav_pass:
            try:
                from config import settings
                nav_url = getattr(settings, "NAVIDROME_URL", nav_url).rstrip("/")
                nav_user = getattr(settings, "NAVIDROME_ADMIN_USER", nav_user)
                nav_pass = getattr(settings, "NAVIDROME_ADMIN_PASS", "")
            except Exception:
                pass
        if not nav_pass:
            return
        salt = secrets.token_hex(4)
        tok = hashlib.md5(f"{nav_pass}{salt}".encode()).hexdigest()
        async with httpx.AsyncClient(timeout=8.0) as client:
            await client.get(
                f"{nav_url}/rest/startScan.view",
                params={"u": nav_user, "t": tok, "s": salt, "v": "1.16.1", "c": "nexus-universal", "f": "json"},
            )
    except Exception:
        pass


async def fetch_spotify_embed_entity(kind: str, spotify_id: str) -> dict:
    url = f"https://open.spotify.com/embed/{kind}/{spotify_id}"
    async with httpx.AsyncClient(timeout=15.0, follow_redirects=True, headers=BROWSER_HEADERS) as client:
        resp = await client.get(url)
        resp.raise_for_status()
        m = re.search(r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>', resp.text, re.DOTALL)
        if not m:
            raise ValueError(f"Could not locate __NEXT_DATA__ in Spotify embed for {kind}/{spotify_id}")
        data = json.loads(m.group(1))
        return data.get("props", {}).get("pageProps", {}).get("state", {}).get("data", {}).get("entity", {})


async def download_track_resilient(
    artist: str,
    title: str,
    dest_path: Path,
    task_id: str = "rescue",
    r=None,
    progress_cb=None,
) -> tuple[bool, str]:
    """4-tier fallback waterfall with live per-song progress and single-line log callbacks."""
    dest_path.parent.mkdir(parents=True, exist_ok=True)
    if dest_path.exists() and dest_path.stat().st_size > 50000:
        return True, "cached"

    yt_bin = get_yt_bin()
    primary_artist, clean_title = clean_search_terms(artist, title)
    display_name = f"{artist} - {title}"

    tiers = [
        ("Tier 1 (YT Exact)", f"ytsearch3:{artist} - {title} audio", True),
        ("Tier 2 (YT Clean)", f"ytsearch3:{primary_artist} {clean_title} song", True),
        ("Tier 3 (YT Broad)", f"ytsearch3:{clean_title} {primary_artist}", False),
        ("Tier 4 (SoundCloud)", f"scsearch1:{primary_artist} {clean_title}", False),
    ]

    async def _notify(pct: float, spd: str, eta: str, msg: str):
        if progress_cb is not None:
            try:
                await progress_cb(pct, spd, eta, msg)
            except TypeError:
                await progress_cb(pct, spd, eta)
        tracker = ACTIVE_TRACK_TRACKER.get()
        if tracker is not None and progress_cb is None:
            await tracker.update_track(tracker.current_index, pct, speed=spd, eta=eta, detail=spd, log_line=msg)

    last_err = "No matching audio stream found"
    for tier_idx, (tier_label, query, apply_filter) in enumerate(tiers, start=1):
        if r is not None and await is_cancelled(r, task_id):
            return False, "cancelled"

        await _notify(
            8.0 + tier_idx * 2.0,
            tier_label,
            "--:--",
            f"{tier_label}: Searching stream for '{display_name}'...",
        )

        sub_tmp = Path(f"/tmp/nexus_res_{task_id}_t{tier_idx}")
        shutil.rmtree(sub_tmp, ignore_errors=True)
        sub_tmp.mkdir(parents=True, exist_ok=True)

        cmd = [
            yt_bin,
            "-x",
            "--audio-format", "mp3",
            "--audio-quality", "0",
            "--embed-thumbnail",
            "--add-metadata",
            "--no-playlist",
            "--ignore-errors",
            "--no-abort-on-error",
            "--max-downloads", "1",
            "--extractor-args", "youtube:player_client=web,android",
            "--newline",
            "--no-colors",
            "-o", str(sub_tmp / "%(title)s.%(ext)s"),
        ]
        if apply_filter:
            cmd.extend(["--match-filter", "duration < 900 & !is_live"])
        cmd.append(query)

        env = os.environ.copy()
        env["PYTHONUNBUFFERED"] = "1"

        try:
            proc = await asyncio.create_subprocess_exec(
                *cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT, env=env
            )
            tail_lines = []
            while True:
                if r is not None and await is_cancelled(r, task_id):
                    proc.kill()
                    shutil.rmtree(sub_tmp, ignore_errors=True)
                    return False, "cancelled"
                line = await proc.stdout.readline()
                if not line:
                    break
                text = line.decode("utf-8", errors="ignore").strip()
                if not text:
                    continue
                tail_lines.append(text)
                if len(tail_lines) > 8:
                    tail_lines.pop(0)

                m_pct = PCT_RE.search(text)
                if m_pct:
                    raw_pct = float(m_pct.group(1))
                    scaled = round(18.0 + raw_pct * 0.68, 1)
                    spd = SPD_RE.search(text).group(1) if SPD_RE.search(text) else "Streaming"
                    eta = ETA_RE.search(text).group(1) if ETA_RE.search(text) else "--:--"
                    await _notify(
                        scaled,
                        spd,
                        eta,
                        f"{tier_label}: Downloading '{display_name}' ({raw_pct:.0f}% @ {spd}, ETA {eta})",
                    )
                elif "[ExtractAudio]" in text:
                    await _notify(91.0, "FFmpeg 320k", "00:02", f"FFmpeg: Converting '{display_name}' to 320kbps MP3...")
                elif "[Metadata]" in text or "[EmbedThumbnail]" in text:
                    await _notify(96.0, "ID3 Tags", "00:01", f"Tagging ID3 metadata & cover art for '{display_name}'...")

            await proc.wait()

            mp3s = [p for p in sub_tmp.glob("*.mp3") if p.stat().st_size > 50000]
            if mp3s:
                shutil.move(str(mp3s[0]), str(dest_path))
                os.utime(str(dest_path), None)
                logger.info(f"[Resilient] Matched via {tier_label}: {display_name}")
                return True, tier_label

            last_err = " | ".join(tail_lines[-3:]) or last_err
            logger.warning(f"[Resilient] {tier_label} missed '{display_name}': {last_err[:180]}")
        except Exception as e:
            last_err = str(e)
            logger.warning(f"[Resilient] {tier_label} exception for '{display_name}': {e}")
        finally:
            shutil.rmtree(sub_tmp, ignore_errors=True)

    return False, last_err


async def rescue_spotify_track_by_id(spotify_track_id: str, dest_path: Path, artist: str = "", title: str = "", r=None) -> bool:
    if dest_path.exists() and dest_path.stat().st_size > 50000:
        return True
    try:
        if not artist or not title:
            entity = await fetch_spotify_embed_entity("track", spotify_track_id)
            title = title or entity.get("name") or entity.get("title") or ""
            artists_list = [a.get("name", "") for a in entity.get("artists", []) if a.get("name")]
            artist = artist or ", ".join(artists_list) or entity.get("subtitle") or ""
        if not title:
            logger.error(f"[Resilient] Could not resolve metadata for Spotify track {spotify_track_id}")
            return False
        ok, info = await download_track_resilient(artist, title, dest_path, task_id=f"sp_{spotify_track_id[:8]}", r=r)
        if not ok:
            logger.error(f"[Resilient] All 4 tiers failed for {spotify_track_id} ({artist} - {title}): {info[:200]}")
        return ok
    except Exception as e:
        logger.error(f"[Resilient] Rescue failed for {spotify_track_id}: {e}")
        return False


async def download_youtube_single(job_data: dict, r):
    task_id = str(job_data.get("task_id", "yt_single"))
    url = str(job_data.get("url", "")).strip()
    owner = job_data.get("owner_username", "admin")

    TRACKS_DIR.mkdir(parents=True, exist_ok=True)
    temp_dir = Path(f"/tmp/yt_dl_{task_id}")
    temp_dir.mkdir(parents=True, exist_ok=True)
    yt_bin = get_yt_bin()

    track_title = job_data.get("title") or "Connecting to YouTube..."
    artist_name = "YouTube"
    cancelled = False

    await push_progress(
        r, task_id, track_title, artist_name, 5.0, "Connecting...", "--:--", owner, "starting",
        log_line=f"Connecting to YouTube for {url}...",
    )

    try:
        dl_cmd = [
            yt_bin, "-x", "--audio-format", "mp3", "--audio-quality", "0",
            "--embed-thumbnail", "--add-metadata", "--write-info-json",
            "--no-playlist", "--newline", "--no-colors",
            "--extractor-args", "youtube:player_client=web,android",
            "-o", str(temp_dir / "%(title)s.%(ext)s"),
            url,
        ]
        env = os.environ.copy()
        env["PYTHONUNBUFFERED"] = "1"
        proc = await asyncio.create_subprocess_exec(
            *dl_cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT, env=env
        )

        current_pct = 5.0
        while True:
            if await is_cancelled(r, task_id):
                cancelled = True
                proc.kill()
                break
            line = await proc.stdout.readline()
            if not line:
                break
            text = line.decode("utf-8", errors="ignore").strip()
            if not text:
                continue

            if "[youtube]" in text and "Downloading" in text:
                current_pct = max(current_pct, 12.0)
                await push_progress(
                    r, task_id, track_title, artist_name, current_pct, "Handshaking", "--:--", owner,
                    log_line=f"YouTube handshake: {text[:100]}",
                )
                continue

            m_info = INFO_RE.search(text)
            if m_info:
                info_path = Path(m_info.group(1).strip())
                if info_path.exists():
                    try:
                        meta = json.loads(info_path.read_text(encoding="utf-8", errors="ignore"))
                        track_title = meta.get("track") or meta.get("title") or track_title
                        artist_name = meta.get("artist") or meta.get("creator") or meta.get("uploader") or "YouTube"
                    except Exception:
                        pass
                current_pct = max(current_pct, 20.0)
                await push_progress(
                    r, task_id, track_title, artist_name, current_pct, "Manifest Locked", "--:--", owner,
                    log_line=f"Manifest locked: {artist_name} - {track_title}",
                )
                continue

            m_dest = DEST_RE.search(text)
            if m_dest and track_title == "Connecting to YouTube...":
                track_title = Path(m_dest.group(1).strip()).stem

            m_pct = PCT_RE.search(text)
            if m_pct:
                raw_pct = float(m_pct.group(1))
                current_pct = round(22.0 + raw_pct * 0.64, 1)
                spd = SPD_RE.search(text).group(1) if SPD_RE.search(text) else "Streaming"
                eta = ETA_RE.search(text).group(1) if ETA_RE.search(text) else "00:01"
                await push_progress(
                    r, task_id, track_title, artist_name, current_pct, spd, eta, owner,
                    log_line=f"Downloading '{artist_name} - {track_title}': {raw_pct:.0f}% @ {spd} (ETA {eta})",
                )
                continue

            if "[ExtractAudio]" in text:
                await push_progress(
                    r, task_id, track_title, artist_name, 91.0, "FFmpeg 320k", "00:02", owner,
                    log_line=f"FFmpeg: Extracting 320kbps MP3 for '{track_title}'...",
                )
            elif "[Metadata]" in text or "[EmbedThumbnail]" in text:
                await push_progress(
                    r, task_id, track_title, artist_name, 96.0, "ID3 Tags", "00:01", owner,
                    log_line=f"Embedding album art & ID3 metadata for '{track_title}'...",
                )

        await proc.wait()

        if cancelled:
            await record_history(r, task_id, track_title, artist_name, "cancelled")
            return

        info_files = list(temp_dir.glob("*.info.json"))
        if info_files:
            try:
                meta = json.loads(info_files[0].read_text(encoding="utf-8", errors="ignore"))
                track_title = meta.get("track") or meta.get("title") or track_title
                artist_name = meta.get("artist") or meta.get("creator") or meta.get("uploader") or artist_name
            except Exception:
                pass

        mp3s = list(temp_dir.glob("*.mp3"))
        if mp3s and mp3s[0].stat().st_size > 50000:
            final_name = f"{sanitize_filename(artist_name)} - {sanitize_filename(track_title)}.mp3"
            dest = TRACKS_DIR / final_name
            shutil.move(str(mp3s[0]), str(dest))
            os.utime(str(dest), None)
            await push_progress(
                r, task_id, track_title, artist_name, 100.0, "Complete", "00:00", owner,
                log_line=f"Saved to /mnt/audio_pool/music/tracks/{final_name}",
            )
            await record_history(r, task_id, track_title, artist_name, "completed", final_name)
        else:
            await record_history(r, task_id, track_title, artist_name, "failed")
    finally:
        await r.hdel("nexus:downloads:active", task_id)
        await r.srem("nexus:downloads:cancelled", task_id)
        shutil.rmtree(temp_dir, ignore_errors=True)
        await r.publish("nexus:events", json.dumps({"event": "QUEUE_SYNC"}))


async def download_youtube_playlist(job_data: dict, r):
    task_id = str(job_data.get("task_id", "yt_pl"))
    url = str(job_data.get("url", "")).strip()
    owner = job_data.get("owner_username", "admin")

    TRACKS_DIR.mkdir(parents=True, exist_ok=True)
    PLAYLISTS_DIR.mkdir(parents=True, exist_ok=True)
    temp_dir = Path(f"/tmp/yt_pl_{task_id}")
    temp_dir.mkdir(parents=True, exist_ok=True)
    yt_bin = get_yt_bin()

    playlist_title = f"YouTube_Playlist_{task_id}"
    track_names: list[str] = []
    cancelled = False

    await push_progress(
        r, task_id, "Resolving YouTube Playlist...", "YouTube Playlist", 5.0, "Probing...", "--:--", owner, "starting",
        log_line=f"Fetching YouTube playlist manifest for {url}...",
    )

    try:
        try:
            probe = await asyncio.create_subprocess_exec(
                yt_bin, "--flat-playlist", "--dump-single-json", url,
                stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
            )
            p_out, _ = await asyncio.wait_for(probe.communicate(), timeout=25.0)
            if probe.returncode == 0 and p_out:
                pdata = json.loads(p_out.decode("utf-8", errors="ignore"))
                playlist_title = pdata.get("title") or playlist_title
                for idx, entry in enumerate(pdata.get("entries") or [], start=1):
                    if not isinstance(entry, dict):
                        continue
                    e_title = entry.get("title") or f"Track {idx}"
                    e_artist = entry.get("uploader") or entry.get("channel") or ""
                    track_names.append(f"{e_artist} - {e_title}" if e_artist and e_artist not in e_title else e_title)
        except Exception as e:
            logger.warning(f"[Universal] YT playlist probe warning: {e}")

        if not track_names:
            track_names = [f"{playlist_title} (Resolving tracks...)"]

        tracker = PlaylistTelemetryTracker(r, task_id, playlist_title, "YouTube Playlist", owner, track_names)
        await tracker.emit(force=True)

        safe_slug = slugify(playlist_title, f"yt_playlist_{task_id}")
        playlist_folder = PLAYLISTS_DIR / safe_slug
        playlist_folder.mkdir(parents=True, exist_ok=True)

        dl_cmd = [
            yt_bin, "-x", "--audio-format", "mp3", "--audio-quality", "0",
            "--embed-thumbnail", "--add-metadata", "--yes-playlist",
            "--ignore-errors", "--no-abort-on-error", "--newline", "--no-colors",
            "--extractor-args", "youtube:player_client=web,android",
            "-o", str(temp_dir / "%(playlist_index)03d - %(artist,uploader,creator|YouTube)s - %(track,title)s.%(ext)s"),
            url,
        ]
        env = os.environ.copy()
        env["PYTHONUNBUFFERED"] = "1"
        proc = await asyncio.create_subprocess_exec(
            *dl_cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT, env=env
        )

        cur_idx = 0
        while True:
            if await is_cancelled(r, task_id):
                cancelled = True
                proc.kill()
                break
            line = await proc.stdout.readline()
            if not line:
                break
            text = line.decode("utf-8", errors="ignore").strip()
            if not text:
                continue

            m_item = ITEM_RE.search(text)
            if m_item:
                if cur_idx > 0 and (cur_idx - 1) < len(tracker.tracks) and tracker.tracks[cur_idx - 1]["status"] == "downloading":
                    await tracker.mark_done(cur_idx - 1)
                cur_idx = int(m_item.group(1))
                tot_items = int(m_item.group(2))
                while len(tracker.tracks) < tot_items:
                    tracker.tracks.append({
                        "index": len(tracker.tracks) + 1,
                        "name": f"Track {len(tracker.tracks) + 1}",
                        "status": "queued",
                        "percent": 0.0,
                        "detail": "Queued",
                    })
                await tracker.start_track(cur_idx - 1)
                continue

            zero_idx = max(cur_idx - 1, 0)
            m_dest = DEST_RE.search(text)
            if m_dest and zero_idx < len(tracker.tracks):
                stem = re.sub(r"^\d{3}\s*-\s*", "", Path(m_dest.group(1).strip()).stem)
                if stem:
                    tracker.tracks[zero_idx]["name"] = stem

            m_pct = PCT_RE.search(text)
            if m_pct and zero_idx < len(tracker.tracks):
                raw_pct = float(m_pct.group(1))
                spd = SPD_RE.search(text).group(1) if SPD_RE.search(text) else "Streaming"
                eta = ETA_RE.search(text).group(1) if ETA_RE.search(text) else "--:--"
                t_name = tracker.tracks[zero_idx]["name"]
                await tracker.update_track(
                    zero_idx,
                    round(10.0 + raw_pct * 0.78, 1),
                    speed=spd,
                    eta=eta,
                    detail=f"{raw_pct:.0f}% • {spd}",
                    log_line=f"[{zero_idx + 1}/{len(tracker.tracks)}] Downloading '{t_name}': {raw_pct:.0f}% @ {spd} (ETA {eta})",
                )
            elif "[ExtractAudio]" in text and zero_idx < len(tracker.tracks):
                t_name = tracker.tracks[zero_idx]["name"]
                await tracker.update_track(
                    zero_idx, 92.0, speed="FFmpeg 320k", eta="00:02", detail="FFmpeg 320k",
                    log_line=f"[{zero_idx + 1}/{len(tracker.tracks)}] FFmpeg converting '{t_name}' to 320kbps MP3...",
                )
            elif ("[Metadata]" in text or "[EmbedThumbnail]" in text) and zero_idx < len(tracker.tracks):
                t_name = tracker.tracks[zero_idx]["name"]
                await tracker.update_track(
                    zero_idx, 97.0, speed="ID3 Tags", eta="00:01", detail="ID3 Tags",
                    log_line=f"[{zero_idx + 1}/{len(tracker.tracks)}] Tagging metadata & artwork for '{t_name}'...",
                )

        await proc.wait()

        if cancelled:
            await record_history(r, task_id, playlist_title, "YouTube Playlist", "cancelled")
            return

        if cur_idx > 0 and (cur_idx - 1) < len(tracker.tracks) and tracker.tracks[cur_idx - 1]["status"] == "downloading":
            await tracker.mark_done(cur_idx - 1)

        await tracker.set_log(f"Finalizing {safe_slug}.m3u8 & moving tracks to /mnt/audio_pool/music/tracks/...", speed="Indexing")

        mp3_files = sorted(temp_dir.glob("*.mp3"))
        m3u8_lines = ["#EXTM3U", f"#PLAYLIST:{playlist_title}"]
        downloaded = []

        for f in mp3_files:
            if f.stat().st_size > 50000:
                stem = re.sub(r"^\d{3}\s*-\s*", "", f.stem)
                clean_name = sanitize_filename(stem) + ".mp3"
                dest = TRACKS_DIR / clean_name
                if not dest.exists():
                    shutil.move(str(f), str(dest))
                else:
                    f.unlink(missing_ok=True)
                os.utime(str(dest), None)
                downloaded.append(clean_name)
                m3u8_lines.append(f"../../tracks/{clean_name}")

        if downloaded:
            m3u8_file = playlist_folder / f"{safe_slug}.m3u8"
            m3u8_file.write_text("\n".join(m3u8_lines), encoding="utf-8")
            os.utime(str(m3u8_file), None)
            await record_history(r, task_id, playlist_title, f"YouTube Playlist ({len(downloaded)} songs)", "completed", f"{safe_slug}.m3u8")
        else:
            await record_history(r, task_id, playlist_title, "YouTube Playlist", "failed")
    finally:
        await r.hdel("nexus:downloads:active", task_id)
        await r.srem("nexus:downloads:cancelled", task_id)
        shutil.rmtree(temp_dir, ignore_errors=True)
        await r.publish("nexus:events", json.dumps({"event": "QUEUE_SYNC"}))


async def download_spotify_single(job_data: dict, r):
    task_id = str(job_data.get("task_id", "sp_single"))
    raw_url = str(job_data.get("url", "")).strip()
    owner = job_data.get("owner_username", "admin")

    TRACKS_DIR.mkdir(parents=True, exist_ok=True)
    track_title = "Resolving Spotify Track..."
    artist_name = "Spotify"

    await push_progress(
        r, task_id, track_title, artist_name, 5.0, "Resolving...", "--:--", owner, "starting",
        log_line=f"Resolving Spotify track link: {raw_url}...",
    )

    try:
        url = await resolve_spotify_url(raw_url)
        m_id = SPOTIFY_TRACK_RE.search(url)
        track_id = m_id.group(1) if m_id else (str(job_data.get("spotify_track_id") or "").strip())
        if not track_id:
            raise ValueError(f"Invalid Spotify track URL: {raw_url}")

        artist_name, track_title = await resolve_spotify_track_metadata(track_id)
        final_name = f"{sanitize_filename(artist_name)} - {sanitize_filename(track_title)}.mp3"
        dest = TRACKS_DIR / final_name

        await push_progress(
            r, task_id, f"{artist_name} - {track_title}", artist_name, 12.0, "Matched", "--:--", owner,
            log_line=f"Spotify track resolved: '{artist_name} - {track_title}' — locating 320kbps stream...",
        )

        async def _cb(pct, spd, eta, msg):
            await push_progress(r, task_id, f"{artist_name} - {track_title}", artist_name, pct, spd, eta, owner, log_line=msg)

        ok, tier_info = await download_track_resilient(
            artist_name, track_title, dest, task_id=task_id, r=r, progress_cb=_cb
        )
        if tier_info == "cancelled":
            await record_history(r, task_id, track_title, artist_name, "cancelled")
        elif ok:
            await trigger_navidrome_quick_scan()
            await push_progress(
                r, task_id, f"{artist_name} - {track_title}", artist_name, 100.0, "Complete", "00:00", owner,
                log_line=f"Saved /mnt/audio_pool/music/tracks/{final_name} ({tier_info})",
            )
            await record_history(r, task_id, track_title, artist_name, "completed", final_name)
        else:
            logger.error(f"[Universal] All 4 tiers failed for Spotify single '{artist_name} - {track_title}': {tier_info}")
            await record_history(r, task_id, track_title, artist_name, "failed")
    except Exception as e:
        logger.error(f"[Universal] Spotify single error: {e}")
        await record_history(r, task_id, track_title, artist_name, "failed")
    finally:
        await r.hdel("nexus:downloads:active", task_id)
        await r.srem("nexus:downloads:cancelled", task_id)
        await r.publish("nexus:events", json.dumps({"event": "QUEUE_SYNC"}))


async def download_spotify_playlist(job_data: dict, r):
    task_id = str(job_data.get("task_id", "sp_pl"))
    url = str(job_data.get("url", "")).strip()
    owner = job_data.get("owner_username", "admin")

    TRACKS_DIR.mkdir(parents=True, exist_ok=True)
    PLAYLISTS_DIR.mkdir(parents=True, exist_ok=True)

    url = await resolve_spotify_url(url)
    m_id = SPOTIFY_PLAYLIST_RE.search(url)
    playlist_id = m_id.group(1) if m_id else ""
    playlist_title = f"Spotify_Playlist_{playlist_id[:8] or task_id}"
    cancelled = False

    await push_progress(
        r, task_id, "Fetching Spotify Playlist...", "Spotify Playlist", 5.0, "Probing...", "--:--", owner, "starting",
        log_line=f"Connecting to Spotify playlist {playlist_id or url}...",
    )

    try:
        if not playlist_id:
            raise ValueError(f"Invalid Spotify playlist URL: {url}")

        entity = await fetch_spotify_embed_entity("playlist", playlist_id)
        playlist_title = entity.get("name") or entity.get("title") or playlist_title
        track_list = entity.get("trackList") or []
        total = len(track_list)
        if total == 0:
            raise ValueError(f"Spotify embed returned 0 tracks for playlist {playlist_id}")

        track_names = [
            f"{item.get('subtitle') or 'Unknown Artist'} - {item.get('title') or f'Track {i}'}"
            for i, item in enumerate(track_list, start=1)
        ]
        tracker = PlaylistTelemetryTracker(r, task_id, playlist_title, "Spotify Playlist", owner, track_names)
        await tracker.emit(force=True)

        safe_slug = slugify(playlist_title, f"sp_playlist_{playlist_id[:8]}")
        playlist_folder = PLAYLISTS_DIR / safe_slug
        playlist_folder.mkdir(parents=True, exist_ok=True)

        m3u8_lines = ["#EXTM3U", f"#PLAYLIST:{playlist_title}"]
        downloaded = []

        for zero_idx, item in enumerate(track_list):
            if await is_cancelled(r, task_id):
                cancelled = True
                break

            t_title = item.get("title") or f"Track {zero_idx + 1}"
            t_artist = item.get("subtitle") or "Unknown Artist"
            clean_name = f"{sanitize_filename(t_artist)} - {sanitize_filename(t_title)}.mp3"
            dest = TRACKS_DIR / clean_name

            if dest.exists() and dest.stat().st_size > 50000:
                os.utime(str(dest), None)
                downloaded.append(clean_name)
                m3u8_lines.append(f"../../tracks/{clean_name}")
                await tracker.mark_cached(zero_idx)
                continue

            await tracker.start_track(zero_idx)

            async def _cb(sub_pct, spd, eta, msg):
                await tracker.update_track(
                    zero_idx, sub_pct, speed=spd, eta=eta, detail=f"{sub_pct:.0f}% • {spd}", log_line=msg
                )

            ok, tier_info = await download_track_resilient(
                t_artist, t_title, dest, task_id=f"{task_id}_{zero_idx}", r=r, progress_cb=_cb
            )
            if tier_info == "cancelled":
                cancelled = True
                break
            if ok:
                downloaded.append(clean_name)
                m3u8_lines.append(f"../../tracks/{clean_name}")
                await tracker.mark_done(zero_idx, detail=tier_info)
            else:
                await tracker.mark_failed(zero_idx, reason=tier_info)

        if cancelled:
            await record_history(r, task_id, playlist_title, "Spotify Playlist", "cancelled")
            return

        if downloaded:
            await tracker.set_log(f"Writing {safe_slug}.m3u8 ({len(downloaded)}/{total} tracks) for Navidrome...", speed="Indexing")
            m3u8_file = playlist_folder / f"{safe_slug}.m3u8"
            m3u8_file.write_text("\n".join(m3u8_lines), encoding="utf-8")
            os.utime(str(m3u8_file), None)
            await record_history(r, task_id, playlist_title, f"Spotify Playlist ({len(downloaded)}/{total} songs)", "completed", f"{safe_slug}.m3u8")
        else:
            await record_history(r, task_id, playlist_title, "Spotify Playlist", "failed")
    except Exception as e:
        logger.error(f"[Universal] Spotify playlist error: {e}")
        await record_history(r, task_id, playlist_title, "Spotify Playlist", "failed")
    finally:
        await r.hdel("nexus:downloads:active", task_id)
        await r.srem("nexus:downloads:cancelled", task_id)
        await r.publish("nexus:events", json.dumps({"event": "QUEUE_SYNC"}))


async def dispatch_universal_job(job_data: dict, r):
    task_type = job_data.get("task_type")
    if task_type == "youtube_single":
        await download_youtube_single(job_data, r)
    elif task_type == "youtube_playlist":
        await download_youtube_playlist(job_data, r)
    elif task_type == "spotify_single":
        await download_spotify_single(job_data, r)
    elif task_type == "spotify_playlist":
        await download_spotify_playlist(job_data, r)
