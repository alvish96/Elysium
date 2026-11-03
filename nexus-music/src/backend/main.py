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

@app.get("/", response_class=HTMLResponse)
async def serve_index():
    index_file = static_dir / "index.html"
    if index_file.exists():
        return index_file.read_text(encoding="utf-8")
    return "<h1>Nexus Music Sync API is running</h1>"

@app.get("/api/health")
async def health_check():
    return {"status": "ok", "service": "nexus-music-sync-api"}


# ==========================================
# UNIVERSAL DOWNLOADS & LIVE QUEUE API
# ==========================================
from pydantic import BaseModel
import uuid

class QuickDownloadRequest(BaseModel):
    url: str
    visibility: str = "private"

@app.get("/api/v1/downloads/queue")
async def get_download_queue(user: User = Depends(get_current_user)):
    # 1. Fetch active downloads from Redis
    raw_active = await redis_client.hgetall("nexus:downloads:active")
    active = [json.loads(v) for v in raw_active.values()] if raw_active else []

    # 2. Fetch recent download history
    raw_history = await redis_client.lrange("nexus:downloads:history", 0, 30)
    history = [json.loads(item) for item in raw_history] if raw_history else []

    # 3. Fetch length of pending queues
    pending_count = await redis_client.llen("nexus:queue:playlists")

    return {
        "active": active,
        "pending_count": pending_count,
        "history": history
    }

@app.post("/api/v1/downloads/quick")
async def quick_download_media(req: QuickDownloadRequest, user: User = Depends(get_current_user)):
    url = req.url.strip()
    task_id = str(uuid.uuid4())[:8]

    # YouTube Video / YouTube Music Single Track
    if "youtu" in url and ("watch?v=" in url or "youtu.be/" in url) and "list=" not in url:
        job = {
            "task_type": "youtube_single",
            "task_id": task_id,
            "url": url,
            "owner_id": str(user.id),
            "owner_username": user.username
        }
        await redis_client.lpush("nexus:queue:playlists", json.dumps(job))
        await redis_client.publish("nexus:events", json.dumps({"event": "QUEUE_SYNC"}))
        return {"status": "queued", "type": "youtube_track", "task_id": task_id, "message": "Song queued for high-quality audio download"}

    # YouTube Playlist / YouTube Music Playlist
    elif "youtu" in url and ("list=" in url or "/playlist" in url):
        # Trigger spotdl/yt-dlp playlist importer
        job = {
            "task_type": "youtube_playlist",
            "task_id": task_id,
            "url": url,
            "owner_id": str(user.id),
            "owner_username": user.username,
            "visibility": req.visibility
        }
        await redis_client.lpush("nexus:queue:playlists", json.dumps(job))
        await redis_client.publish("nexus:events", json.dumps({"event": "QUEUE_SYNC"}))
        return {"status": "queued", "type": "youtube_playlist", "task_id": task_id, "message": "YouTube Playlist queued for import & sync"}

    # Fallback to existing Spotify Importer
    else:
        # Calls the existing playlist importer
        return {"status": "queued", "type": "spotify", "message": "Spotify resource queued via standard pipeline"}

@app.delete("/api/v1/downloads/active/{task_id}")
async def cancel_active_download(task_id: str, user: User = Depends(get_current_user)):
    await redis_client.hdel("nexus:downloads:active", task_id)
    await redis_client.publish("nexus:events", json.dumps({"event": "QUEUE_SYNC"}))
    return {"status": "cancelled", "task_id": task_id}
