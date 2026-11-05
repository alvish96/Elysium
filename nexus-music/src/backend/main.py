import os
import sys
import json
import uuid
from fastapi import FastAPI, Depends, HTTPException
from pydantic import BaseModel
import redis.asyncio as aioredis
from navidrome_bridge import get_current_user
from models import User

from navidrome_bridge import get_current_user
from models import User
import redis.asyncio as aioredis
from pydantic import BaseModel
import uuid
import json
import asyncio
from pathlib import Path
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles

from database import init_db
from navidrome_bridge import router as auth_router
from spotify_service import router as spotify_router
from playlists_router import router as playlists_router
from websocket_manager import router as ws_router, redis_event_listener

@asynccontextmanager
async def lifespan(app: FastAPI):
    print("Initializing Nexus Sync Database Schema...")
    await init_db()
    listener_task = asyncio.create_task(redis_event_listener())
    yield
    listener_task.cancel()
    try:
        await listener_task
    except asyncio.CancelledError:
        pass

app = FastAPI(
    title="Nexus Music Sync API",
    version="1.0.0",
    docs_url="/api/docs",
    redoc_url="/api/redoc",
    openapi_url="/api/openapi.json",
    lifespan=lifespan
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth_router)
app.include_router(spotify_router)
app.include_router(playlists_router)
app.include_router(ws_router)

static_dir = Path("/app/static")
static_dir.mkdir(parents=True, exist_ok=True)
app.mount("/static", StaticFiles(directory=str(static_dir)), name="static")

@app.get("/")
async def serve_main_galactic_ui():
    return FileResponse("/app/static/v2/index.html")

@app.get("/api/health")
async def health_check():
    return {"status": "ok", "service": "nexus-music-sync-api"}


# === UNIVERSAL DOWNLOADS API ===
REDIS_HOST = os.getenv("REDIS_HOST", "nexus-sync-redis-svc.media.svc.cluster.local")
dl_redis = aioredis.from_url(f"redis://{REDIS_HOST}:6379/0", decode_responses=True)

class YouTubeDownloadRequest(BaseModel):
    url: str
    visibility: str = "private"

@app.post("/api/v1/downloads/youtube")
async def queue_youtube_download(req: YouTubeDownloadRequest, user: User = Depends(get_current_user)):
    url = req.url.strip()
    if not ("youtube.com" in url or "youtu.be" in url):
        raise HTTPException(status_code=400, detail="Invalid YouTube URL. Please enter a valid YouTube or YouTube Music link.")

    task_id = str(uuid.uuid4())[:8]
    is_playlist = ("list=" in url or "/playlist" in url)
    task_type = "youtube_playlist" if is_playlist else "youtube_single"

    job = {
        "task_type": task_type,
        "task_id": task_id,
        "url": url,
        "owner_id": str(user.id),
        "owner_username": user.username,
        "visibility": req.visibility
    }

    await dl_redis.lpush("nexus:queue:playlists", json.dumps(job))
    await dl_redis.publish("nexus:events", json.dumps({"event": "QUEUE_SYNC"}))

    return {
        "status": "queued",
        "task_id": task_id,
        "task_type": task_type,
        "message": f"Queued {'playlist' if is_playlist else 'song'} for download"
    }

@app.get("/api/v1/downloads/queue")
async def get_download_queue(user: User = Depends(get_current_user)):
    # 1. Currently downloading tasks
    try:
        raw_active = await dl_redis.hgetall("nexus:downloads:active")
        active = [json.loads(v) for v in raw_active.values()] if raw_active else []
    except Exception:
        active = []

    # 2. Tasks waiting in line in Redis
    try:
        raw_pending = await dl_redis.lrange("nexus:queue:playlists", 0, -1)
        pending = []
        for raw in raw_pending:
            try:
                p = json.loads(raw)
                pending.append({
                    "id": p.get("task_id", "queued"),
                    "title": p.get("title", p.get("url", "Queued Track")),
                    "url": p.get("url", ""),
                    "type": p.get("task_type", "youtube_single"),
                    "owner": p.get("owner_username", "admin")
                })
            except Exception:
                pass
    except Exception:
        pending = []

    # 3. Finished download history
    try:
        raw_history = await dl_redis.lrange("nexus:downloads:history", 0, 30)
        history = [json.loads(v) for v in raw_history] if raw_history else []
    except Exception:
        history = []

    return {
        "active": active,
        "pending": pending,
        "pending_count": len(pending),
        "history": history
    }

from fastapi.responses import FileResponse

@app.get("/v2")
async def serve_v2_workspace():
    return FileResponse("/app/static/v2/index.html")



@app.get("/v1")
@app.get("/legacy")
async def serve_legacy_v1_ui():
    return FileResponse("/app/static/index.html")

@app.get("/tracks")
async def serve_downloaded_tracks_page():
    return FileResponse("/app/static/v2/tracks.html")

@app.get("/api/v1/downloads/tracks")
async def list_downloaded_tracks():
    tracks_dir = Path("/mnt/audio_pool/music/tracks")
    items = []
    total_bytes = 0
    if tracks_dir.exists():
        files = sorted(
            [f for f in tracks_dir.glob("*.mp3") if f.is_file()],
            key=lambda x: x.stat().st_mtime,
            reverse=True
        )
        for f in files:
            st = f.stat()
            total_bytes += st.st_size
            stem = f.stem
            if " - " in stem:
                artist, title = stem.split(" - ", 1)
            else:
                artist, title = "YouTube Audio", stem
            items.append({
                "filename": f.name,
                "title": title.strip(),
                "artist": artist.strip(),
                "size_mb": round(st.st_size / (1024 * 1024), 2),
                "modified_at": st.st_mtime
            })
    return {
        "total_count": len(items),
        "total_size_mb": round(total_bytes / (1024 * 1024), 2),
        "tracks": items
    }

@app.get("/api/v1/downloads/tracks/stream/{filename}")
async def stream_downloaded_track(filename: str):
    safe_name = os.path.basename(filename)
    target = Path("/mnt/audio_pool/music/tracks") / safe_name
    if not target.exists() or not target.is_file():
        raise HTTPException(status_code=404, detail="Track file not found")
    return FileResponse(str(target), media_type="audio/mpeg", filename=safe_name)
# === END V2.1 ROUTES ===

# === QUEUE CANCELLATION & PROFILE PLAYLIST DELETION ROUTES ===
import shutil, json, os, redis
from pathlib import Path

def _get_sync_redis():
    return redis.Redis(
        host=os.getenv("REDIS_HOST", "nexus-sync-redis-svc.media.svc.cluster.local"),
        port=6379,
        db=0,
        decode_responses=True
    )

@app.delete("/api/v1/downloads/queue/{item_id}")
async def cancel_or_remove_download(item_id: str):
    r = _get_sync_redis()
    removed_active = False
    removed_pending = 0

    # 1. Signal worker subprocess to kill yt-dlp if currently running
    r.sadd("nexus:downloads:cancelled", item_id)

    # 2. Remove from active downloads hash immediately
    if r.hexists("nexus:downloads:active", item_id):
        r.hdel("nexus:downloads:active", item_id)
        removed_active = True

    for k, v in list(r.hgetall("nexus:downloads:active").items()):
        try:
            data = json.loads(v)
            if str(data.get("id")) == item_id or str(data.get("title")) == item_id:
                r.sadd("nexus:downloads:cancelled", k)
                r.hdel("nexus:downloads:active", k)
                removed_active = True
        except Exception:
            pass

    # 3. Remove matching item from pending Redis queue (by task_id, playlist_id, url, or index)
    pending_raw = r.lrange("nexus:queue:playlists", 0, -1)
    for idx, raw in enumerate(pending_raw):
        try:
            job = json.loads(raw)
            job_id = str(job.get("task_id") or job.get("playlist_id") or job.get("id") or "")
            job_url = str(job.get("url") or "")
            if item_id in (job_id, job_url, f"idx-{idx}"):
                r.lrem("nexus:queue:playlists", 0, raw)
                removed_pending += 1
        except Exception:
            if item_id == f"idx-{idx}":
                r.lrem("nexus:queue:playlists", 0, raw)
                removed_pending += 1

    r.publish("nexus:events", json.dumps({"event": "QUEUE_SYNC"}))
    return {
        "status": "cancelled",
        "item_id": item_id,
        "removed_active": removed_active,
        "removed_pending": removed_pending
    }

@app.delete("/api/v1/playlists/profile/{playlist_id}")
async def delete_playlist_from_profile(playlist_id: str, slug: str = ""):
    r = _get_sync_redis()

    # 1. Record in deleted playlists set so it stays hidden from profile views
    r.sadd("nexus:playlists:deleted", playlist_id)
    if slug and slug not in ("", "unindexed"):
        r.sadd("nexus:playlists:deleted", slug)

    # 2. Remove from pending download queue if queued
    for raw in r.lrange("nexus:queue:playlists", 0, -1):
        try:
            job = json.loads(raw)
            if job.get("playlist_id") == playlist_id or job.get("task_id") == playlist_id:
                r.lrem("nexus:queue:playlists", 0, raw)
        except Exception:
            pass

    # 3. Remove ONLY the playlist .m3u8 folder (NEVER touch /mnt/audio_pool/music/tracks/*.mp3)
    removed_folder = False
    if slug and slug not in ("", "unindexed", "/", "."):
        safe_slug = os.path.basename(slug.strip("/"))
        pl_dir = Path("/mnt/audio_pool/music/playlists") / safe_slug
        if pl_dir.exists() and pl_dir.is_dir():
            shutil.rmtree(pl_dir, ignore_errors=True)
            removed_folder = True

    return {
        "status": "deleted",
        "playlist_id": playlist_id,
        "removed_playlist_folder": removed_folder,
        "tracks_preserved": True
    }

@app.get("/api/v1/playlists/deleted")
async def get_deleted_profile_playlists():
    r = _get_sync_redis()
    return {"deleted_ids": list(r.smembers("nexus:playlists:deleted") or [])}

@app.post("/api/v1/playlists/deleted/restore")
async def restore_deleted_profile_playlists():
    r = _get_sync_redis()
    r.delete("nexus:playlists:deleted")
    return {"status": "restored"}
# === END QUEUE CANCELLATION & PROFILE PLAYLIST DELETION ROUTES ===
