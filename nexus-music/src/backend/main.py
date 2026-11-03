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
