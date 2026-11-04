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

@app.get("/", response_class=HTMLResponse)
async def serve_index():
    index_file = static_dir / "index.html"
    if index_file.exists():
        return index_file.read_text(encoding="utf-8")
    return "<h1>Nexus Music Sync API is running</h1>"

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


@app.get("/v2.0")
async def serve_v20_backup():
    return FileResponse("/app/static/v2.0/index.html")
