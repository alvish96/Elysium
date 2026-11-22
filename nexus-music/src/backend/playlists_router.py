import os
import re
import json
import base64
import shutil
import sqlite3
from pathlib import Path
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
import redis.asyncio as redis
import httpx

from config import settings, decrypt_value
from database import get_db
from models import User, Playlist, PlaylistTrack
from navidrome_bridge import get_current_user
from schemas import PlaylistConfigureRequest, PlaylistConfigureResponse


# --- INSTANT TELEMETRY & PRIORITY ENQUEUE HELPER ---
async def enqueue_playlist_sync_immediate(r_client, job_payload: dict, playlist_title: str = "Spotify Playlist"):
    import json, uuid
    task_id = job_payload.setdefault("task_id", f"pl_{uuid.uuid4().hex[:8]}")
    owner = job_payload.get("owner_username", "admin")
    pid = str(job_payload.get("playlist_id") or job_payload.get("spotify_playlist_id") or "")
    if pid and playlist_title:
        await r_client.hset("nexus:playlist:names", pid, playlist_title)
    # Priority front-of-line push so manual user syncs start immediately
    await r_client.lpush("nexus:queue:playlists", json.dumps(job_payload))
    # Immediately seed active stream banner so UI shows progress right away
    await r_client.hset("nexus:downloads:active", task_id, json.dumps({
        "id": task_id,
        "playlist_id": pid,
        "title": f"{playlist_title} — Initializing Sync...",
        "artist": "Spotify Sync",
        "percent": 2.0,
        "speed": "Starting",
        "eta": "Connecting...",
        "status": "starting",
        "owner": owner
    }))
    await r_client.publish("nexus:events", json.dumps({"event": "QUEUE_SYNC"}))
    return task_id

router = APIRouter(prefix="/api/v1/playlists", tags=["Playlists"])

class PlaylistImportRequest(BaseModel):
    url_or_id: str
    visibility: str = "private"  # "private" or "public"
    auto_sync: bool = True       # True = Import & Sync, False = Import Only

NAVIDROME_DB_PATH = os.getenv("NAVIDROME_DB_PATH", "/mnt/navidrome/navidrome.db")

def sanitize_slug(text: str) -> str:
    text = re.sub(r"[^\w\s-]", "", text.strip())
    return re.sub(r"[-\s]+", "_", text).lower()

def extract_spotify_playlist_id(input_str: str) -> str:
    input_str = input_str.strip()
    match = re.search(r"playlist/([a-zA-Z0-9]{22})", input_str)
    if match:
        return match.group(1)
    if re.match(r"^[a-zA-Z0-9]{22}$", input_str):
        return input_str
    raise HTTPException(status_code=400, detail="Invalid Spotify playlist URL or ID.")

async def get_client_credentials_token() -> str:
    auth_str = f"{settings.SPOTIFY_CLIENT_ID}:{settings.SPOTIFY_CLIENT_SECRET}"
    b64_auth = base64.b64encode(auth_str.encode()).decode()
    
    async with httpx.AsyncClient(timeout=10.0) as client:
        resp = await client.post(
            "https://accounts.spotify.com/api/token",
            data={"grant_type": "client_credentials"},
            headers={
                "Authorization": f"Basic {b64_auth}",
                "Content-Type": "application/x-www-form-urlencoded"
            }
        )
        if resp.status_code != 200:
            raise HTTPException(status_code=500, detail=f"Failed to obtain Spotify App token: {resp.text}")
        return resp.json()["access_token"]

def set_navidrome_playlist_owner_and_visibility(username: str, playlist_name: str, folder_slug: str, is_public: bool):
    """Enforces multi-user isolation in Navidrome SQLite DB."""
    db_paths = [NAVIDROME_DB_PATH, "/mnt/internal/appdata/navidrome/navidrome.db"]
    target_db = next((p for p in db_paths if os.path.exists(p)), None)
    if not target_db:
        return

    try:
        conn = sqlite3.connect(target_db, timeout=10.0)
        cur = conn.cursor()
        cur.execute("SELECT id FROM user WHERE user_name = ?", (username,))
        row = cur.fetchone()
        if not row:
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
    except Exception as e:
        print(f"Error syncing Navidrome DB: {e}")

async def update_navidrome_playlist_visibility(user: User, playlist_name: str, folder_slug: str, is_public: bool):
    set_navidrome_playlist_owner_and_visibility(user.username, playlist_name, folder_slug, is_public)

    token = decrypt_value(user.subsonic_token_enc)
    salt = decrypt_value(user.subsonic_salt_enc)
    if not token or not salt:
        return

    subsonic_params = f"u={user.username}&t={token}&s={salt}&v=1.16.1&c=nexus-sync&f=json"
    playlists_url = f"{settings.NAVIDROME_URL}/rest/getPlaylists.view?{subsonic_params}"

    async with httpx.AsyncClient(timeout=8.0) as client:
        try:
            resp = await client.get(playlists_url)
            if resp.status_code != 200:
                return

            data = resp.json().get("subsonic-response", {})
            all_pl = data.get("playlists", {}).get("playlist", [])
            if isinstance(all_pl, dict):
                all_pl = [all_pl]

            matching = [pl for pl in all_pl if pl.get("name", "") in (playlist_name, folder_slug, f"[{folder_slug}]")]
            if not matching:
                return

            primary_id = matching[0].get("id")
            pub_val = "true" if is_public else "false"
            update_url = f"{settings.NAVIDROME_URL}/rest/updatePlaylist.view?playlistId={primary_id}&public={pub_val}&{subsonic_params}"
            await client.get(update_url)
        except Exception as e:
            print(f"Warning: Could not update Navidrome visibility via Subsonic API: {e}")

@router.get("/search-public")
async def search_spotify_public_playlists(
    q: str = Query(..., min_length=1),
    current_user: User = Depends(get_current_user)
):
    token = await get_client_credentials_token()
    url = f"https://api.spotify.com/v1/search?q={httpx.URL(q)}&type=playlist&limit=12"
    async with httpx.AsyncClient(timeout=10.0) as client:
        resp = await client.get(url, headers={"Authorization": f"Bearer {token}"})
        if resp.status_code != 200:
            return []
        data = resp.json()
        items = data.get("playlists", {}).get("items", [])
        results = []
        for it in items:
            if not it or not it.get("id"):
                continue
            images = it.get("images") or []
            cover = images[0]["url"] if images else None
            results.append({
                "id": it["id"],
                "name": it.get("name", "Untitled"),
                "description": it.get("description", ""),
                "cover_url": cover,
                "total_tracks": (it.get("tracks") or {}).get("total", 0),
                "owner_name": (it.get("owner") or {}).get("display_name", "Spotify")
            })
        return results

@router.get("/imported")
async def list_imported_playlists(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    stmt = select(Playlist).where(
        Playlist.owner_id == current_user.id,
        Playlist.is_imported == True
    )
    res = await db.execute(stmt)
    playlists = res.scalars().all()

    return [
        {
            "id": p.spotify_playlist_id,
            "name": p.name,
            "cover_url": p.cover_url,
            "total_tracks": p.total_tracks,
            "downloaded_tracks": p.downloaded_tracks,
            "is_synced": p.is_synced,
            "visibility": p.visibility,
            "folder_slug": p.folder_slug,
            "sync_status": p.sync_status,
            "last_synced_at": p.last_synced_at.isoformat() if p.last_synced_at else None
        }
        for p in playlists
    ]

@router.post("/import")
async def import_playlist_by_url(
    req: PlaylistImportRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    # SPOTIFY_SINGLE_INTERCEPT: handle individual Spotify track links & short links
    _raw_in = str(getattr(req, "url_or_id", None) or getattr(req, "url", "") or "").strip()
    if any(h in _raw_in.lower() for h in ("spotify.link/", "spoti.fi/", "spotify.app.link/")):
        try:
            import httpx as _hx
            async with _hx.AsyncClient(timeout=10.0, follow_redirects=True) as _hc:
                _raw_in = str((await _hc.get(_raw_in)).url)
                if hasattr(req, "url_or_id"):
                    req.url_or_id = _raw_in
        except Exception:
            pass
    import re as _re
    _m_tr = _re.search(r"(?:open\.spotify\.com/(?:intl-[a-z]{2,3}/)?track/|spotify:track:)([A-Za-z0-9]{22})", _raw_in)
    if _m_tr:
        import json as _js, os as _os, uuid as _uu
        import redis.asyncio as _ar
        _tid = _uu.uuid4().hex[:8]
        _uname = getattr(current_user, "username", "admin")
        _uid = str(getattr(current_user, "id", "admin"))
        _rhost = _os.getenv("REDIS_HOST", "nexus-sync-redis-svc.media.svc.cluster.local")
        _rurl = _os.getenv("REDIS_URL") or f"redis://{_rhost}:6379/0"
        _rc = _ar.from_url(_rurl, decode_responses=True)
        try:
            _sp_label = "Spotify Track"
            try:
                import asyncio as _as
                from universal_downloader import resolve_spotify_track_metadata as _rsm
                _a, _t = await _as.wait_for(_rsm(_m_tr.group(1)), timeout=4.0)
                if _t:
                    _sp_label = f"{_a} — {_t}" if _a and _a.lower() != "spotify" else _t
                    await _rc.hset("nexus:url:titles", _raw_in, _sp_label)
            except Exception:
                pass
            _job = {
                "task_type": "spotify_single",
                "task_id": _tid,
                "url": _raw_in,
                "spotify_track_id": _m_tr.group(1),
                "title": _sp_label,
                "owner_id": _uid,
                "owner_username": _uname,
                "visibility": getattr(req, "visibility", "private"),
            }
            await _rc.lpush("nexus:queue:playlists", _js.dumps(_job))
            if await _rc.hlen("nexus:downloads:active") == 0:
                await _rc.hset("nexus:downloads:active", _tid, _js.dumps({
                    "id": _tid,
                    "title": _sp_label,
                    "artist": "Spotify",
                    "percent": 2.0,
                    "overall_percent": 2.0,
                    "speed": "Starting",
                    "eta": "--:--",
                    "status": "starting",
                    "owner": _uname,
                    "log_line": "Queued Spotify track — resolving metadata...",
                }))
            await _rc.publish("nexus:events", _js.dumps({"event": "QUEUE_SYNC"}))
        finally:
            await (_rc.aclose() if hasattr(_rc, 'aclose') else _rc.close())
        return {
            "status": "queued",
            "type": "spotify_single",
            "task_id": _tid,
            "message": "Spotify track queued for immediate 320kbps MP3 download",
        }
    spotify_playlist_id = extract_spotify_playlist_id(req.url_or_id)
    token = await get_client_credentials_token()

    url = f"https://api.spotify.com/v1/playlists/{spotify_playlist_id}?fields=id,name,description,images,tracks.total"
    async with httpx.AsyncClient(timeout=10.0) as client:
        resp = await client.get(url, headers={"Authorization": f"Bearer {token}"})
        if resp.status_code != 200:
            raise HTTPException(
                status_code=400,
                detail=f"Could not resolve Spotify playlist. Ensure playlist is Public or Unlisted. Error: {resp.text}"
            )
        data = resp.json()

    name = data.get("name", "Imported Playlist")
    slug = sanitize_slug(name) or spotify_playlist_id
    images = data.get("images") or []
    cover_url = images[0]["url"] if images else None
    total_tracks = (data.get("tracks") or {}).get("total", 0)

    stmt = select(Playlist).where(
        Playlist.owner_id == current_user.id,
        Playlist.spotify_playlist_id == spotify_playlist_id
    )
    res = await db.execute(stmt)
    playlist = res.scalar_one_or_none()

    if not playlist:
        playlist = Playlist(
            spotify_playlist_id=spotify_playlist_id,
            owner_id=current_user.id,
            name=name,
            folder_slug=slug,
            cover_url=cover_url,
            total_tracks=total_tracks,
            is_synced=req.auto_sync,
            is_imported=True,
            visibility=req.visibility,
            sync_status="queued" if req.auto_sync else "idle"
        )
        db.add(playlist)
    else:
        playlist.is_imported = True
        playlist.visibility = req.visibility
        playlist.cover_url = cover_url or playlist.cover_url
        playlist.total_tracks = total_tracks or playlist.total_tracks
        if req.auto_sync:
            playlist.is_synced = True
            playlist.sync_status = "queued"

    await db.commit()
    await db.refresh(playlist)

    r = redis.Redis(host=settings.REDIS_HOST, port=settings.REDIS_PORT, decode_responses=True)
    if req.auto_sync:
        job_payload = {
            "action": "sync_playlist",
            "playlist_id": playlist.id,
            "spotify_playlist_id": playlist.spotify_playlist_id,
            "owner_id": current_user.id,
            "visibility": playlist.visibility,
            "folder_slug": playlist.folder_slug
        }
        await r.lpush("nexus:queue:playlists", json.dumps(job_payload))

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

    msg = f"Imported '{name}' and queued download." if req.auto_sync else f"Imported '{name}' successfully (Sync is OFF)."
    return {
        "status": "ok",
        "message": msg,
        "playlist_id": spotify_playlist_id
    }

@router.delete("/{spotify_playlist_id}")
async def delete_imported_playlist(
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
        raise HTTPException(status_code=404, detail="Playlist not found.")

    pl_dir = Path(settings.MUSIC_ROOT) / "playlists" / playlist.folder_slug
    if pl_dir.exists():
        shutil.rmtree(pl_dir, ignore_errors=True)

    await db.delete(playlist)
    await db.commit()

    # Remove from Navidrome
    set_navidrome_playlist_owner_and_visibility(current_user.username, playlist.name, playlist.folder_slug, False)

    return {"status": "ok", "message": f"Deleted playlist {playlist.name}"}

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
    playlists_dir = music_root / "playlists" / slug
    playlists_dir.mkdir(parents=True, exist_ok=True)

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

    # Immediately synchronize Navidrome database ownership & visibility
    await update_navidrome_playlist_visibility(
        current_user,
        playlist.name,
        playlist.folder_slug,
        playlist.visibility == "public"
    )

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
        await r.lpush("nexus:queue:playlists", json.dumps(job_payload))

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
        message="Playlist visibility updated successfully.",
        playlist_id=playlist.spotify_playlist_id,
        folder_path=str(playlists_dir),
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
    await r.lpush("nexus:queue:playlists", json.dumps(job_payload))

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
        Playlist.is_synced == True,
        (Playlist.owner_id == current_user.id) | (Playlist.visibility == "public")
    )
    res = await db.execute(stmt)
    playlists = list(res.scalars().all())

    # Resolve deleted playlist IDs/slugs from Redis so hidden items never show in Server Vault
    deleted_set = set()
    try:
        r_del = redis.Redis(host=settings.REDIS_HOST, port=settings.REDIS_PORT, decode_responses=True)
        deleted_set = set(await r_del.smembers("nexus:playlists:deleted") or [])
        await (r_del.aclose() if hasattr(r_del, 'aclose') else r_del.close())
    except Exception:
        pass

    # Map owner IDs to usernames
    users_res = await db.execute(select(User))
    owner_map = {u.id: u.username for u in users_res.scalars().all()}

    # Deduplicate by folder_slug, preferring current user's row + valid 22-char Spotify ID
    sp_id_re = re.compile(r"^[A-Za-z0-9]{22}$")
    deduped = {}
    for pl in playlists:
        slug_key = (pl.folder_slug or pl.name or str(pl.id)).strip().lower()
        sp_id = str(pl.spotify_playlist_id or "")
        if sp_id in deleted_set or slug_key in deleted_set or str(pl.id) in deleted_set:
            continue

        rank = (
            pl.owner_id == current_user.id,
            bool(sp_id_re.match(sp_id)),
            int(pl.downloaded_tracks or 0),
            str(pl.last_synced_at or ""),
        )
        prev = deduped.get(slug_key)
        if prev is None or rank > prev[0]:
            deduped[slug_key] = (rank, pl)

    music_root = Path(settings.MUSIC_ROOT)
    vault_items = []

    for _, pl in deduped.values():
        folder_path = music_root / "playlists" / pl.folder_slug
        m3u8_file = folder_path / f"{pl.folder_slug}.m3u8"
        on_disk_count = 0
        if m3u8_file.exists():
            on_disk_count = sum(
                1 for line in m3u8_file.read_text(encoding="utf-8", errors="ignore").splitlines()
                if line.strip() and not line.strip().startswith("#")
            )

        vault_items.append({
            "id": pl.id,
            "spotify_playlist_id": pl.spotify_playlist_id,
            "name": pl.name,
            "folder_slug": pl.folder_slug,
            "visibility": pl.visibility,
            "cover_url": pl.cover_url,
            "is_synced": bool(pl.is_synced),
            "is_owner": pl.owner_id == current_user.id,
            "owner_username": owner_map.get(pl.owner_id, current_user.username),
            "sync_status": pl.sync_status,
            "downloaded_tracks": max(int(pl.downloaded_tracks or 0), on_disk_count),
            "total_tracks": max(int(pl.total_tracks or 0), on_disk_count),
            "on_disk_count": on_disk_count,
            "folder_path": str(folder_path),
            "last_synced_at": pl.last_synced_at.isoformat() if pl.last_synced_at else None
        })

    vault_items.sort(key=lambda x: (x["name"] or "").lower())
    return vault_items
