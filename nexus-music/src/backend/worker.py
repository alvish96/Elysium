from datetime import datetime, timezone
#!/usr/bin/env python3
import asyncio
import json
import logging
import os
import re
import shutil
import sqlite3
from datetime import datetime
from pathlib import Path
from typing import Optional, List, Dict

import httpx
import redis.asyncio as redis
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from config import settings, decrypt_value
from database import AsyncSessionLocal
from models import User, Playlist, Track, PlaylistTrack, SpotifyAccount
from spotify_service import get_valid_spotify_token

logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] [%(levelname)s] [Worker] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S"
)
logger = logging.getLogger("nexus-worker")

SPOTIFY_API_BASE = "https://api.spotify.com/v1"
APPRISE_URL = os.getenv("APPRISE_URL", "http://apprise-svc.monitoring.svc.cluster.local:8000/notify/")
NAVIDROME_DB_PATH = os.getenv("NAVIDROME_DB_PATH", "/mnt/navidrome/navidrome.db")

def sanitize_filename(name: str) -> str:
    cleaned = re.sub(r'[\\/*?:"<>|]', "", name)
    cleaned = cleaned.strip(". ")
    return cleaned or "untitled"

async def publish_event(r: redis.Redis, event_data: dict):
    try:
        await r.publish("nexus:events", json.dumps(event_data))
    except Exception as e:
        logger.warning(f"Could not publish WebSocket event: {e}")

async def send_notification(title: str, body: str):
    try:
        async with httpx.AsyncClient(timeout=6.0) as client:
            await client.post(APPRISE_URL, json={"title": title, "body": body})
    except Exception as e:
        logger.warning(f"Apprise notification failed: {e}")

def set_navidrome_playlist_owner_and_visibility(username: str, playlist_name: str, folder_slug: str, is_public: bool):
    """Directly sets owner_id and public flag in Navidrome SQLite database."""
    db_paths = [NAVIDROME_DB_PATH, "/mnt/internal/appdata/navidrome/navidrome.db"]
    target_db = next((p for p in db_paths if os.path.exists(p)), None)
    if not target_db:
        logger.warning(f"Navidrome DB not accessible at {NAVIDROME_DB_PATH}.")
        return

    try:
        conn = sqlite3.connect(target_db, timeout=10.0)
        cur = conn.cursor()
        cur.execute("SELECT id FROM user WHERE user_name = ?", (username,))
        row = cur.fetchone()
        if not row:
            logger.warning(f"User '{username}' not found in Navidrome user table.")
            conn.close()
            return

        user_id = row[0]
        pub_int = 1 if is_public else 0
        cur.execute("""
            UPDATE playlist 
            SET owner_id = ?, public = ?
            WHERE path LIKE ? OR name = ? OR name = ?;
        """, (user_id, pub_int, f"%/{folder_slug}/%", playlist_name, folder_slug))
        conn.commit()
        conn.close()
        logger.info(f"Assigned Navidrome playlist '{playlist_name}' to user '{username}' (owner_id: {user_id}, public: {is_public}).")
    except Exception as e:
        logger.error(f"Error updating Navidrome playlist ownership in SQLite: {e}")

async def trigger_navidrome_scan_and_visibility(user: User, playlist_name: str, folder_slug: str, is_public: bool):
    token = decrypt_value(user.subsonic_token_enc)
    salt = decrypt_value(user.subsonic_salt_enc)
    if not token or not salt:
        return

    subsonic_params = f"u={user.username}&t={token}&s={salt}&v=1.16.1&c=nexus-worker&f=json"
    scan_url = f"{settings.NAVIDROME_URL}/rest/startScan.view?{subsonic_params}"

    async with httpx.AsyncClient(timeout=10.0) as client:
        try:
            await client.get(scan_url)
            logger.info("Triggered Navidrome Subsonic library scan.")
        except Exception as e:
            logger.warning(f"Navidrome scan trigger failed: {e}")
            return

    # Wait for scanner to register m3u8, then set ownership in DB
    await asyncio.sleep(2)
    set_navidrome_playlist_owner_and_visibility(user.username, playlist_name, folder_slug, is_public)

async def download_track_spotdl(spotify_track_id: str, master_file: Path) -> bool:
    scratch_dir = Path("/tmp/spotdl") / spotify_track_id
    scratch_dir.mkdir(parents=True, exist_ok=True)

    spotdl_bin = "/opt/worker-venv/bin/spotdl"
    if not Path(spotdl_bin).exists():
        spotdl_bin = "spotdl"

    cmd = [
        spotdl_bin,
        "download",
        f"https://open.spotify.com/track/{spotify_track_id}",
        "--output", str(scratch_dir / "{artist} - {title}.{ext}"),
        "--format", "mp3",
        "--bitrate", "320k",
        "--simple-tui",
        "--log-level", "INFO"
    ]

    try:
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        stdout, stderr = await proc.communicate()

        mp3_matches = list(scratch_dir.glob("*.mp3"))
        if mp3_matches and mp3_matches[0].stat().st_size > 50000:
            shutil.move(str(mp3_matches[0]), str(master_file))
            logger.info(f"Track {spotify_track_id} saved to master pool: {master_file.name}")
            return True
        else:
            logger.warning(f"SpotDL download finished but no MP3 produced for {spotify_track_id}: {stderr.decode()[:200]}")
            return False
    except Exception as e:
        logger.error(f"Execution error downloading track {spotify_track_id}: {e}")
        return False
    finally:
        shutil.rmtree(scratch_dir, ignore_errors=True)

async def fetch_tracks_via_spotdl_save(spotify_playlist_id: str) -> List[Dict]:
    cache_dir = Path("/tmp/spotdl_cache")
    cache_dir.mkdir(parents=True, exist_ok=True)
    save_file = cache_dir / f"{spotify_playlist_id}.spotdl"

    spotdl_bin = "/opt/worker-venv/bin/spotdl"
    if not Path(spotdl_bin).exists():
        spotdl_bin = "spotdl"

    cmd = [
        spotdl_bin,
        "save",
        f"https://open.spotify.com/playlist/{spotify_playlist_id}",
        "--save-file", str(save_file),
        "--simple-tui",
        "--log-level", "INFO"
    ]

    logger.info(f"Executing spotdl save for playlist {spotify_playlist_id}...")
    try:
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        stdout, stderr = await proc.communicate()

        if save_file.exists():
            data = json.loads(save_file.read_text(encoding="utf-8"))
            tracks = []
            for item in data:
                sp_id = item.get("song_id")
                if not sp_id and item.get("url"):
                    sp_id = item["url"].split("/track/")[-1].split("?")[0]
                if not sp_id:
                    continue

                artists = ", ".join(item.get("artists", [])) or item.get("artist", "Unknown Artist")
                tracks.append({
                    "spotify_track_id": sp_id,
                    "title": item.get("name", "Unknown Title"),
                    "artist": artists,
                    "album": item.get("album_name", ""),
                    "duration_ms": int(item.get("duration", 0) * 1000) if item.get("duration") else 0,
                    "cover_url": item.get("cover_url")
                })
            logger.info(f"Resolved {len(tracks)} tracks via spotdl save.")
            return tracks
        else:
            logger.warning(f"spotdl save failed: {stderr.decode()[:300]}")
            return []
    except Exception as e:
        logger.error(f"Error executing spotdl save: {e}")
        return []
    finally:
        if save_file.exists():
            try:
                save_file.unlink()
            except Exception:
                pass

async def fetch_playlist_tracks(token: str, spotify_playlist_id: str) -> List[Dict]:
    tracks = []
    url = f"{SPOTIFY_API_BASE}/playlists/{spotify_playlist_id}/items?limit=100"

    headers = {"Authorization": f"Bearer {token}"} if token else {}
    async with httpx.AsyncClient(timeout=12.0) as client:
        while url:
            resp = await client.get(url, headers=headers)
            if resp.status_code == 200:
                data = resp.json()
                for item in data.get("items", []):
                    t = item.get("item") or item.get("track")
                    if not t or not t.get("id"):
                        continue
                    artists = ", ".join([a.get("name", "") for a in t.get("artists", [])])
                    album = (t.get("album") or {}).get("name", "")
                    images = (t.get("album") or {}).get("images") or []
                    cover_url = images[0]["url"] if images else None

                    tracks.append({
                        "spotify_track_id": t["id"],
                        "title": t.get("name", "Unknown Title"),
                        "artist": artists or "Unknown Artist",
                        "album": album,
                        "duration_ms": t.get("duration_ms", 0),
                        "cover_url": cover_url
                    })
                url = data.get("next")
            else:
                logger.warning(f"Spotify /items returned {resp.status_code}. Using spotdl resolver...")
                break

    if tracks:
        return tracks

    return await fetch_tracks_via_spotdl_save(spotify_playlist_id)

async def sync_playlist_task(job_data: dict, r: redis.Redis):
    playlist_id = job_data["playlist_id"]
    spotify_playlist_id = job_data["spotify_playlist_id"]
    owner_id = job_data["owner_id"]

    logger.info(f"--> Starting Sync for playlist {spotify_playlist_id}...")

    async with AsyncSessionLocal() as db:
        stmt = select(Playlist).where(Playlist.id == playlist_id)
        res = await db.execute(stmt)
        playlist = res.scalar_one_or_none()
        if not playlist or not playlist.is_synced:
            logger.info(f"Playlist {playlist_id} is not marked for sync. Skipping.")
            return

        stmt_u = select(User).where(User.id == owner_id)
        res_u = await db.execute(stmt_u)
        user = res_u.scalar_one_or_none()
        if not user:
            logger.error(f"User {owner_id} not found.")
            return

        playlist.sync_status = "syncing"
        await db.commit()

        try:
            spotify_token = await get_valid_spotify_token(db, user.id)
        except Exception:
            spotify_token = ""

        tracks_meta = await fetch_playlist_tracks(spotify_token, spotify_playlist_id)
        if not tracks_meta:
            logger.warning(f"No tracks found for playlist {spotify_playlist_id}.")
            playlist.sync_status = "failed"
            await db.commit()
            return

        playlist.total_tracks = len(tracks_meta)
        await db.commit()

    music_root = Path(settings.MUSIC_ROOT)
    master_pool = music_root / ".master_pool"
    master_pool.mkdir(parents=True, exist_ok=True)
    
    tracks_dir = music_root / "tracks"
    tracks_dir.mkdir(parents=True, exist_ok=True)

    target_dir = music_root / "playlists" / playlist.folder_slug
    target_dir.mkdir(parents=True, exist_ok=True)

    downloaded_count = 0
    playlist_track_filenames: List[str] = []

    for idx, t_meta in enumerate(tracks_meta, start=1):
        sp_tid = t_meta["spotify_track_id"]
        master_file = master_pool / f"{sp_tid}.mp3"

        if not (master_file.exists() and master_file.stat().st_size > 50000):
            lock_key = f"lock:track:{sp_tid}"
            acquired = await r.set(lock_key, "worker", nx=True, ex=300)
            if acquired:
                try:
                    await download_track_spotdl(sp_tid, master_file)
                finally:
                    await r.delete(lock_key)
            else:
                for _ in range(12):
                    await asyncio.sleep(2)
                    if master_file.exists() and master_file.stat().st_size > 50000:
                        break

        if master_file.exists() and master_file.stat().st_size > 50000:
            safe_artist = sanitize_filename(t_meta["artist"])
            safe_title = sanitize_filename(t_meta["title"])
            link_name = f"{safe_artist} - {safe_title}.mp3"
            central_track_dest = tracks_dir / link_name

            if not central_track_dest.exists():
                try:
                    os.link(master_file, central_track_dest)
                except FileExistsError:
                    pass
                except Exception as e:
                    logger.warning(f"Could not link {master_file} to {central_track_dest}: {e}")

            playlist_track_filenames.append(link_name)
            downloaded_count += 1

        await publish_event(r, {
            "event": "TRACK_PROGRESS",
            "playlist_id": spotify_playlist_id,
            "folder_slug": playlist.folder_slug,
            "current": idx,
            "total": len(tracks_meta),
            "track_title": t_meta["title"],
            "downloaded_count": downloaded_count
        })

    m3u8_file = target_dir / f"{playlist.folder_slug}.m3u8"
    m3u8_lines = ["#EXTM3U", f"#PLAYLIST:{playlist.name}"]
    for fn in playlist_track_filenames:
        m3u8_lines.append(f"../../tracks/{fn}")

    m3u8_file.write_text("\n".join(m3u8_lines) + "\n")
    logger.info(f"Generated static playlist file: {m3u8_file} ({len(playlist_track_filenames)} tracks)")

    async with AsyncSessionLocal() as db:
        stmt = select(Playlist).where(Playlist.id == playlist_id)
        res = await db.execute(stmt)
        p = res.scalar_one_or_none()
        if p:
            p.downloaded_tracks = downloaded_count
            p.total_tracks = len(tracks_meta)
            p.sync_status = "completed"
            p.last_synced_at = datetime.utcnow()
            await db.commit()

    await trigger_navidrome_scan_and_visibility(
        user,
        playlist.name,
        playlist.folder_slug,
        playlist.visibility == "public"
    )

    await publish_event(r, {
        "event": "SYNC_COMPLETED",
        "playlist_id": spotify_playlist_id,
        "folder_slug": playlist.folder_slug,
        "downloaded_count": downloaded_count,
        "total_tracks": len(tracks_meta)
    })

    await send_notification(
        title="🎵 Nexus Music Sync",
        body=f"Synced playlist '{playlist.name}' for {user.username} ({downloaded_count}/{len(tracks_meta)} tracks ready)."
    )
    logger.info(f"✅ Finished syncing playlist: {playlist.name} (Owner: {user.username})")

# === YOUTUBE ENGINE ===
async def download_youtube_single(job_data: dict, r: redis.Redis):
    task_id = job_data.get("task_id", "unknown")
    url = job_data.get("url", "")
    owner_username = job_data.get("owner_username", "admin")

    tracks_dir = Path("/mnt/audio_pool/music/tracks")
    tracks_dir.mkdir(parents=True, exist_ok=True)
    temp_dir = Path(f"/tmp/yt_dl_{task_id}")
    temp_dir.mkdir(parents=True, exist_ok=True)

    yt_bin = "/opt/worker-venv/bin/yt-dlp"
    if not Path(yt_bin).exists():
        yt_bin = "yt-dlp"

    logger.info(f"[Worker] Processing YouTube download task {task_id} for URL: {url}")

    await r.hset("nexus:downloads:active", task_id, json.dumps({
        "id": task_id,
        "title": "Resolving track metadata...",
        "artist": "YouTube",
        "percent": 0.0,
        "speed": "0 KiB/s",
        "eta": "--:--",
        "status": "starting",
        "owner": owner_username
    }))
    await r.publish("nexus:events", json.dumps({"event": "QUEUE_SYNC"}))

    track_title = "Unknown Track"
    artist_name = "YouTube Music"
    try:
        probe = await asyncio.create_subprocess_exec(
            yt_bin, "--dump-json", "--no-playlist", url,
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE
        )
        p_out, _ = await probe.communicate()
        if probe.returncode == 0:
            meta = json.loads(p_out.decode("utf-8", errors="ignore"))
            track_title = meta.get("track") or meta.get("title") or "Unknown Track"
            artist_name = meta.get("artist") or meta.get("uploader") or meta.get("creator") or "YouTube"
    except Exception as e:
        logger.warning(f"[Worker] Metadata probe warning: {e}")

    out_tmpl = str(temp_dir / "%(title)s.%(ext)s")
    dl_cmd = [
        yt_bin,
        "-x",
        "--audio-format", "mp3",
        "--audio-quality", "0",
        "--embed-thumbnail",
        "--add-metadata",
        "--no-playlist",
        "--newline",
        "-o", out_tmpl,
        url
    ]

    proc = await asyncio.create_subprocess_exec(
        *dl_cmd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.STDOUT
    )

    pct_re = re.compile(r'[download]\s+(\d+\.?\d*)%\s+of\s+~?(\S+)\s+at\s+(\S+)\s+ETA\s+(\S+)')

    while True:
        line = await proc.stdout.readline()
        if not line:
            break
        text = line.decode("utf-8", errors="ignore").strip()
        m = pct_re.search(text)
        if m:
            pct = float(m.group(1))
            spd = m.group(3)
            eta = m.group(4)
            progress_payload = {
                "id": task_id,
                "title": track_title,
                "artist": artist_name,
                "percent": pct,
                "speed": spd,
                "eta": eta,
                "status": "downloading",
                "owner": owner_username
            }
            await r.hset("nexus:downloads:active", task_id, json.dumps(progress_payload))
            await r.publish("nexus:events", json.dumps({"event": "TRACK_PROGRESS", "data": progress_payload}))

    await proc.wait()

    mp3s = list(temp_dir.glob("*.mp3"))
    if mp3s and mp3s[0].stat().st_size > 50000:
        safe_artist = sanitize_filename(artist_name)
        safe_title = sanitize_filename(track_title)
        final_filename = f"{safe_artist} - {safe_title}.mp3"
        dest = tracks_dir / final_filename
        shutil.move(str(mp3s[0]), str(dest))
        import os
        os.utime(str(dest), None)

        history_entry = {
            "id": task_id,
            "title": track_title,
            "artist": artist_name,
            "status": "completed",
            "file": final_filename,
            "completed_at": datetime.now(timezone.utc).isoformat()
        }
        await r.lpush("nexus:downloads:history", json.dumps(history_entry))
        await r.ltrim("nexus:downloads:history", 0, 49)
        logger.info(f"[Worker] Saved audio file to tracks directory: {dest}")
    else:
        history_entry = {
            "id": task_id,
            "title": track_title,
            "artist": artist_name,
            "status": "failed",
            "completed_at": datetime.now(timezone.utc).isoformat()
        }
        await r.lpush("nexus:downloads:history", json.dumps(history_entry))
        logger.warning(f"[Worker] Download finished without producing valid MP3 for {url}")

    await r.hdel("nexus:downloads:active", task_id)
    shutil.rmtree(temp_dir, ignore_errors=True)
    await r.publish("nexus:events", json.dumps({"event": "QUEUE_SYNC"}))
# === END YOUTUBE ENGINE ===

async def queue_worker_loop():
    logger.info("Connecting to Redis queue 'nexus:queue:playlists'...")
    r = redis.Redis(host=settings.REDIS_HOST, port=settings.REDIS_PORT, decode_responses=True)

    while True:
        try:
            item = await r.blpop("nexus:queue:playlists", timeout=5)
            if item:
                _, payload_raw = item
                try:
                    job_data = json.loads(payload_raw)
                    task_type = job_data.get('task_type', 'sync_playlist')
                    if task_type == 'youtube_single':
                        await download_youtube_single(job_data, r)
                    else:
                        task_type = job_data.get('task_type', 'sync_playlist')
                        if task_type == 'youtube_single':
                            await download_youtube_single(job_data, r)
                        else:
                            await sync_playlist_task(job_data, r)
                except Exception as ex:
                    logger.error(f"Error executing sync task: {ex}", exc_info=True)
        except asyncio.CancelledError:
            break
        except Exception as e:
            logger.error(f"Queue pop error: {e}. Retrying in 5s...")
            await asyncio.sleep(5)

async def periodic_2hr_scheduler():
    logger.info("Periodic 2-hour scheduler started.")
    r = redis.Redis(host=settings.REDIS_HOST, port=settings.REDIS_PORT, decode_responses=True)

    while True:
        await asyncio.sleep(7200)
        logger.info("Checking active playlists for scheduled sync...")
        try:
            async with AsyncSessionLocal() as db:
                stmt = select(Playlist).where(Playlist.is_synced == True)
                res = await db.execute(stmt)
                for pl in res.scalars().all():
                    job = {
                        "action": "sync_playlist",
                        "playlist_id": pl.id,
                        "spotify_playlist_id": pl.spotify_playlist_id,
                        "owner_id": pl.owner_id,
                        "visibility": pl.visibility,
                        "folder_slug": pl.folder_slug
                    }
                    await r.rpush("nexus:queue:playlists", json.dumps(job))
        except asyncio.CancelledError:
            break
        except Exception as e:
            logger.error(f"Scheduler error: {e}")

async def main():
    logger.info("Starting Nexus Music Background Worker with Navidrome Multi-User Isolation...")
    await asyncio.gather(
        queue_worker_loop(),
        periodic_2hr_scheduler()
    )

if __name__ == "__main__":
    asyncio.run(main())


# =========================================================================
# YOUTUBE DOWNLOAD ENGINE & DISPATCHER
# =========================================================================
