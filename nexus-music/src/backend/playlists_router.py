import os
import re
import json
from pathlib import Path
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
import redis.asyncio as redis
import httpx

from config import settings, decrypt_value
from database import get_db
from models import User, Playlist, PlaylistTrack
from navidrome_bridge import get_current_user
from schemas import PlaylistConfigureRequest, PlaylistConfigureResponse

router = APIRouter(prefix="/api/v1/playlists", tags=["Playlists"])

def sanitize_slug(text: str) -> str:
    text = re.sub(r"[^\w\s-]", "", text.strip())
    return re.sub(r"[-\s]+", "_", text).lower()

async def trigger_navidrome_scan(user: User):
    """Triggers Navidrome Subsonic library scan."""
    token = decrypt_value(user.subsonic_token_enc)
    salt = decrypt_value(user.subsonic_salt_enc)
    if not token or not salt:
        return
    url = f"{settings.NAVIDROME_URL}/rest/startScan.view?u={user.username}&t={token}&s={salt}&v=1.16.1&c=nexus-sync&f=json"
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            await client.get(url)
    except Exception as e:
        print(f"Warning: Could not trigger Navidrome scan: {e}")

@router.post("/{spotify_playlist_id}/configure", response_model=PlaylistConfigureResponse)
async def configure_playlist(
    spotify_playlist_id: str,
    req: PlaylistConfigureRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    stmt = select(Playlist).where(
        Playlist.owner_id == current_user.id,
        Playlist.spotify_playlist_id == spotify_playlist_id
    )
    res = await db.execute(stmt)
    playlist = res.scalar_one_or_none()

    slug = sanitize_slug(req.folder_slug) if req.folder_slug else (playlist.folder_slug if playlist else spotify_playlist_id)
    music_root = Path(settings.MUSIC_ROOT)
    master_pool = music_root / ".master_pool"
    master_pool.mkdir(parents=True, exist_ok=True)

    old_visibility = playlist.visibility if playlist else None
    old_slug = playlist.folder_slug if playlist else None

    # Compute target path
    if req.visibility == "public":
        target_dir = music_root / "public" / slug
    else:
        target_dir = music_root / "users" / current_user.username / "private" / slug

    target_dir.mkdir(parents=True, exist_ok=True)

    # 1. Update or Create Database Record
    if not playlist:
        playlist = Playlist(
            spotify_playlist_id=spotify_playlist_id,
            owner_id=current_user.id,
            name=req.folder_slug or slug,
            folder_slug=slug,
            is_synced=req.is_synced,
            visibility=req.visibility,
            sync_status="queued" if req.is_synced else "idle"
        )
        db.add(playlist)
    else:
        playlist.is_synced = req.is_synced
        playlist.visibility = req.visibility
        playlist.folder_slug = slug
        if req.is_synced and playlist.sync_status in ("idle", "failed"):
            playlist.sync_status = "queued"

    await db.commit()
    await db.refresh(playlist)

    # 2. Atomic Hardlink Migration if Visibility or Slug changed
    if old_visibility and (old_visibility != req.visibility or old_slug != slug):
        if old_visibility == "public":
            old_dir = music_root / "public" / old_slug
        else:
            old_dir = music_root / "users" / current_user.username / "private" / old_slug

        if old_dir.exists() and old_dir != target_dir:
            print(f"Migrating tracks from {old_dir} to {target_dir}")
            mp3_files = list(old_dir.glob("*.mp3"))
            for mp3 in mp3_files:
                dest = target_dir / mp3.name
                if not dest.exists():
                    try:
                        os.link(mp3, dest)
                    except Exception as e:
                        print(f"Error linking {mp3} to {dest}: {e}")
                try:
                    mp3.unlink()
                except Exception:
                    pass

            m3u8_file = target_dir / f"{slug}.m3u8"
            m3u8_content = ["#EXTM3U", f"#PLAYLIST:{playlist.name}"]
            for mp3 in sorted(target_dir.glob("*.mp3")):
                m3u8_content.append(mp3.name)
            m3u8_file.write_text("\n".join(m3u8_content) + "\n")

            old_m3u8 = old_dir / f"{old_slug}.m3u8"
            if old_m3u8.exists():
                old_m3u8.unlink()
            try:
                old_dir.rmdir()
            except Exception:
                pass

            await trigger_navidrome_scan(current_user)

    # 3. If Synced is Enabled, Push Job to Redis Queue
    r = redis.Redis(host=settings.REDIS_HOST, port=settings.REDIS_PORT, decode_responses=True)
    if req.is_synced:
        job_payload = {
            "action": "sync_playlist",
            "playlist_id": playlist.id,
            "spotify_playlist_id": playlist.spotify_playlist_id,
            "owner_id": current_user.id,
            "visibility": playlist.visibility,
            "folder_slug": playlist.folder_slug
        }
        await r.rpush("nexus:queue:playlists", json.dumps(job_payload))

    await r.publish("nexus:events", json.dumps({
        "event": "PLAYLIST_CONFIGURED",
        "playlist_id": playlist.spotify_playlist_id,
        "name": playlist.name,
        "is_synced": playlist.is_synced,
        "visibility": playlist.visibility,
        "sync_status": playlist.sync_status,
        "downloaded_tracks": playlist.downloaded_tracks,
        "total_tracks": playlist.total_tracks
    }))

    return PlaylistConfigureResponse(
        status="ok",
        message="Playlist configuration updated successfully.",
        playlist_id=playlist.spotify_playlist_id,
        folder_path=str(target_dir),
        visibility=playlist.visibility,
        is_synced=playlist.is_synced
    )

@router.post("/{spotify_playlist_id}/sync-now")
async def trigger_sync_now(
    spotify_playlist_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    stmt = select(Playlist).where(
        Playlist.owner_id == current_user.id,
        Playlist.spotify_playlist_id == spotify_playlist_id
    )
    res = await db.execute(stmt)
    playlist = res.scalar_one_or_none()
    if not playlist:
        raise HTTPException(status_code=404, detail="Playlist not registered. Please enable sync first.")

    playlist.sync_status = "queued"
    playlist.is_synced = True
    await db.commit()

    r = redis.Redis(host=settings.REDIS_HOST, port=settings.REDIS_PORT, decode_responses=True)
    job_payload = {
        "action": "sync_playlist",
        "playlist_id": playlist.id,
        "spotify_playlist_id": playlist.spotify_playlist_id,
        "owner_id": current_user.id,
        "visibility": playlist.visibility,
        "folder_slug": playlist.folder_slug
    }
    await r.rpush("nexus:queue:playlists", json.dumps(job_payload))

    await r.publish("nexus:events", json.dumps({
        "event": "PLAYLIST_QUEUED",
        "playlist_id": playlist.spotify_playlist_id,
        "name": playlist.name
    }))

    return {"status": "ok", "message": f"Sync queued for {playlist.name}"}

@router.get("/vault")
async def get_vault_overview(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    stmt = select(Playlist).where(
        (Playlist.owner_id == current_user.id) | (Playlist.visibility == "public")
    )
    res = await db.execute(stmt)
    playlists = res.scalars().all()

    music_root = Path(settings.MUSIC_ROOT)
    vault_items = []

    for pl in playlists:
        if pl.visibility == "public":
            folder_path = music_root / "public" / pl.folder_slug
        else:
            folder_path = music_root / "users" / current_user.username / "private" / pl.folder_slug

        on_disk_count = 0
        if folder_path.exists():
            on_disk_count = len(list(folder_path.glob("*.mp3")))

        vault_items.append({
            "id": pl.id,
            "spotify_playlist_id": pl.spotify_playlist_id,
            "name": pl.name,
            "folder_slug": pl.folder_slug,
            "visibility": pl.visibility,
            "cover_url": pl.cover_url,
            "is_owner": pl.owner_id == current_user.id,
            "sync_status": pl.sync_status,
            "downloaded_tracks": pl.downloaded_tracks,
            "total_tracks": pl.total_tracks,
            "on_disk_count": on_disk_count,
            "folder_path": str(folder_path),
            "last_synced_at": pl.last_synced_at.isoformat() if pl.last_synced_at else None
        })

    return vault_items
