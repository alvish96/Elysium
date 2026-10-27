#!/usr/bin/env python3
import asyncio
import json
import logging
import os
import re
import shutil
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

        # Wait briefly for Navidrome to detect the .m3u8 file
        await asyncio.sleep(3)

        try:
            playlists_url = f"{settings.NAVIDROME_URL}/rest/getPlaylists.view?{subsonic_params}"
            resp = await client.get(playlists_url)
            if resp.status_code == 200:
                data = resp.json().get("subsonic-response", {})
                all_pl = data.get("playlists", {}).get("playlist", [])
                if isinstance(all_pl, dict):
                    all_pl = [all_pl]

                for pl in all_pl:
                    p_name = pl.get("name", "")
                    if p_name in (playlist_name, folder_slug, f"[{folder_slug}]"):
                        pl_id = pl.get("id")
                        pub_flag = "true" if is_public else "false"
                        update_url = f"{settings.NAVIDROME_URL}/rest/updatePlaylist.view?playlistId={pl_id}&public={pub_flag}&{subsonic_params}"
                        await client.get(update_url)
                        logger.info(f"Updated Navidrome playlist '{p_name}' (ID: {pl_id}) visibility to public={pub_flag}.")
                        break
        except Exception as e:
            logger.warning(f"Could not update playlist visibility in Navidrome: {e}")

async def download_track_spotdl(spotify_track_id: str, master_file: Path) -> bool:
    """Downloads single track to master pool using spotDL CLI and a scratch temp dir."""
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
            logger.warning(f"SpotDL finished but no MP3 produced for {spotify_track_id}: {stderr.decode()[:200]}")
            return False
    except Exception as e:
        logger.error(f"Execution error downloading track {spotify_track_id}: {e}")
        return False
    finally:
        shutil.rmtree(scratch_dir, ignore_errors=True)

async def fetch_playlist_tracks_from_spotify(token: str, spotify_playlist_id: str) -> List[Dict]:
    """Fetches all tracks for a playlist via Spotify Web API with full pagination."""
    tracks = []
    url = f"{SPOTIFY_API_BASE}/playlists/{spotify_playlist_id}/tracks?limit=100"

    async with httpx.AsyncClient(timeout=15.0) as client:
        while url:
            resp = await client.get(url, headers={"Authorization": f"Bearer {token}"})
            if resp.status_code != 200:
                logger.error(f"Spotify API error ({resp.status_code}): {resp.text}")
                break
            data = resp.json()
            for item in data.get("items", []):
                t = item.get("track")
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

    return tracks

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
            logger.info(f"Playlist {playlist_id} is no longer marked for sync. Skipping.")
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
        except Exception as e:
            logger.error(f"Failed to obtain Spotify token: {e}")
            playlist.sync_status = "failed"
            await db.commit()
            return

        tracks_meta = await fetch_playlist_tracks_from_spotify(spotify_token, spotify_playlist_id)
        playlist.total_tracks = len(tracks_meta)
        await db.commit()

    # Determine destination directory
    music_root = Path(settings.MUSIC_ROOT)
    master_pool = music_root / ".master_pool"
    master_pool.mkdir(parents=True, exist_ok=True)

    if playlist.visibility == "public":
        target_dir = music_root / "public" / playlist.folder_slug
    else:
        target_dir = music_root / "users" / user.username / "private" / playlist.folder_slug

    target_dir.mkdir(parents=True, exist_ok=True)

    downloaded_count = 0

    for idx, t_meta in enumerate(tracks_meta, start=1):
        sp_tid = t_meta["spotify_track_id"]
        master_file = master_pool / f"{sp_tid}.mp3"

        # Check or acquire download lock
        if not (master_file.exists() and master_file.stat().st_size > 50000):
            lock_key = f"lock:track:{sp_tid}"
            acquired = await r.set(lock_key, "worker", nx=True, ex=300)
            if acquired:
                try:
                    await download_track_spotdl(sp_tid, master_file)
                finally:
                    await r.delete(lock_key)
            else:
                # Another worker is downloading; wait briefly
                for _ in range(12):
                    await asyncio.sleep(2)
                    if master_file.exists() and master_file.stat().st_size > 50000:
                        break

        # Create atomic hardlink in playlist target directory
        if master_file.exists() and master_file.stat().st_size > 50000:
            safe_artist = sanitize_filename(t_meta["artist"])
            safe_title = sanitize_filename(t_meta["title"])
            link_name = f"{safe_artist} - {safe_title}.mp3"
            link_dest = target_dir / link_name

            if not link_dest.exists():
                try:
                    os.link(master_file, link_dest)
                except FileExistsError:
                    pass
                except Exception as e:
                    logger.warning(f"Could not hardlink {master_file} to {link_dest}: {e}")

            downloaded_count += 1

        # Emit real-time progress via Redis Pub/Sub
        await publish_event(r, {
            "event": "TRACK_PROGRESS",
            "playlist_id": spotify_playlist_id,
            "folder_slug": playlist.folder_slug,
            "current": idx,
            "total": len(tracks_meta),
            "track_title": t_meta["title"],
            "downloaded_count": downloaded_count
        })

    # Generate or update .m3u8 playlist file
    m3u8_file = target_dir / f"{playlist.folder_slug}.m3u8"
    m3u8_lines = [
        "#EXTM3U",
        f"#PLAYLIST:{playlist.name}"
    ]
    for mp3 in sorted(target_dir.glob("*.mp3")):
        m3u8_lines.append(mp3.name)

    m3u8_file.write_text("\n".join(m3u8_lines) + "\n")
    logger.info(f"Generated playlist file: {m3u8_file}")

    # Update database record
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

    # Trigger Navidrome scanner and update playlist visibility
    await trigger_navidrome_scan_and_visibility(
        user,
        playlist.name,
        playlist.folder_slug,
        playlist.visibility == "public"
    )

    # Broadcast completion event
    await publish_event(r, {
        "event": "SYNC_COMPLETED",
        "playlist_id": spotify_playlist_id,
        "folder_slug": playlist.folder_slug,
        "downloaded_count": downloaded_count,
        "total_tracks": len(tracks_meta)
    })

    # Apprise notification
    await send_notification(
        title="🎵 Nexus Music Sync",
        body=f"Synced playlist '{playlist.name}' ({downloaded_count}/{len(tracks_meta)} tracks ready)."
    )
    logger.info(f"✅ Finished syncing playlist: {playlist.name}")

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
                    await sync_playlist_task(job_data, r)
                except Exception as ex:
                    logger.error(f"Error executing playlist sync task: {ex}", exc_info=True)
        except asyncio.CancelledError:
            break
        except Exception as e:
            logger.error(f"Redis queue pop error: {e}. Retrying in 5s...")
            await asyncio.sleep(5)

async def periodic_2hr_scheduler():
    """Checks all playlists with is_synced=True every 2 hours and enqueues sync tasks."""
    logger.info("Periodic 2-hour playlist scheduler started.")
    r = redis.Redis(host=settings.REDIS_HOST, port=settings.REDIS_PORT, decode_responses=True)

    while True:
        await asyncio.sleep(7200)
        logger.info("Running 2-hour scheduled sync check across active playlists...")
        try:
            async with AsyncSessionLocal() as db:
                stmt = select(Playlist).where(Playlist.is_synced == True)
                res = await db.execute(stmt)
                synced_list = res.scalars().all()
                for pl in synced_list:
                    job = {
                        "action": "sync_playlist",
                        "playlist_id": pl.id,
                        "spotify_playlist_id": pl.spotify_playlist_id,
                        "owner_id": pl.owner_id,
                        "visibility": pl.visibility,
                        "folder_slug": pl.folder_slug
                    }
                    await r.rpush("nexus:queue:playlists", json.dumps(job))
                    logger.info(f"Enqueued scheduled sync for {pl.name}")
        except asyncio.CancelledError:
            break
        except Exception as e:
            logger.error(f"Scheduler error: {e}")

async def main():
    logger.info("Starting Nexus Music Background Worker...")
    await asyncio.gather(
        queue_worker_loop(),
        periodic_2hr_scheduler()
    )

if __name__ == "__main__":
    asyncio.run(main())
