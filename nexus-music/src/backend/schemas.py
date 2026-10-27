from datetime import datetime
from typing import Optional, List
from pydantic import BaseModel, Field

class LoginRequest(BaseModel):
    username: str
    password: str

class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    username: str
    is_admin: bool
    navidrome_id: Optional[str] = None

class UserOut(BaseModel):
    id: str
    username: str
    is_admin: bool
    created_at: datetime

class SpotifyPlaylistOut(BaseModel):
    id: str
    name: str
    description: Optional[str] = None
    cover_url: Optional[str] = None
    total_tracks: int
    is_synced: bool = False
    visibility: str = "private"
    folder_slug: str
    sync_status: str = "idle"
    downloaded_tracks: int = 0
    last_synced_at: Optional[datetime] = None

class PlaylistConfigureRequest(BaseModel):
    is_synced: bool
    visibility: str = Field(default="private", pattern="^(private|public)$")
    folder_slug: Optional[str] = None

class PlaylistConfigureResponse(BaseModel):
    status: str
    message: str
    playlist_id: str
    folder_path: str
    visibility: str
    is_synced: bool
