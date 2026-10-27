import re
import urllib.parse
from datetime import datetime, timedelta
from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.responses import RedirectResponse
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
import httpx

from config import settings, encrypt_value, decrypt_value
from database import get_db
from models import User, SpotifyAccount, Playlist
from navidrome_bridge import get_current_user, create_access_token
from schemas import SpotifyPlaylistOut

router = APIRouter(prefix="/api/v1/spotify", tags=["Spotify"])

SPOTIFY_AUTH_URL = "https://accounts.spotify.com/authorize"
SPOTIFY_TOKEN_URL = "https://accounts.spotify.com/api/token"
SPOTIFY_API_BASE = "https://api.spotify.com/v1"
SCOPES = "playlist-read-private playlist-read-collaborative user-library-read"

def slugify(text: str) -> str:
    text = re.sub(r"[^\w\s-]", "", text.strip())
    return re.sub(r"[-\s]+", "_", text).lower()

async def get_valid_spotify_token(db: AsyncSession, user_id: str) -> str:
    stmt = select(SpotifyAccount).where(SpotifyAccount.user_id == user_id)
    result = await db.execute(stmt)
    account = result.scalar_one_or_none()

    if not account:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No Spotify account connected for this user."
        )

    access_token = decrypt_value(account.access_token_enc)
    refresh_token = decrypt_value(account.refresh_token_enc)

    # Refresh if expired or expiring within 2 minutes
    if datetime.utcnow() >= (account.expires_at - timedelta(seconds=120)):
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.post(
                SPOTIFY_TOKEN_URL,
                data={
                    "grant_type": "refresh_token",
                    "refresh_token": refresh_token,
                    "client_id": settings.SPOTIFY_CLIENT_ID,
                    "client_secret": settings.SPOTIFY_CLIENT_SECRET,
                },
                headers={"Content-Type": "application/x-www-form-urlencoded"}
            )
            if resp.status_code != 200:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Failed to refresh Spotify access token."
                )
            token_data = resp.json()
            access_token = token_data["access_token"]
            expires_in = token_data.get("expires_in", 3600)

            account.access_token_enc = encrypt_value(access_token)
            account.expires_at = datetime.utcnow() + timedelta(seconds=expires_in)
            if "refresh_token" in token_data:
                account.refresh_token_enc = encrypt_value(token_data["refresh_token"])

            await db.commit()

    return access_token

@router.get("/login")
async def spotify_login(current_user: User = Depends(get_current_user)):
    # Sign state with user token to prevent CSRF and identify user on callback
    state = create_access_token({"sub": current_user.id, "username": current_user.username})
    params = {
        "client_id": settings.SPOTIFY_CLIENT_ID,
        "response_type": "code",
        "redirect_uri": settings.SPOTIFY_REDIRECT_URI,
        "scope": SCOPES,
        "state": state,
        "show_dialog": "true"
    }
    url = f"{SPOTIFY_AUTH_URL}?{urllib.parse.urlencode(params)}"
    return {"authorization_url": url}

@router.get("/callback")
async def spotify_callback(
    code: str = Query(...),
    state: str = Query(...),
    db: AsyncSession = Depends(get_db)
):
    from jose import jwt, JWTError
    try:
        payload = jwt.decode(state, settings.JWT_SECRET_KEY, algorithms=[settings.JWT_ALGORITHM])
        user_id = payload.get("sub")
    except JWTError:
        raise HTTPException(status_code=400, detail="Invalid state parameter.")

    stmt = select(User).where(User.id == user_id)
    res = await db.execute(stmt)
    user = res.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found.")

    # Exchange code for Spotify tokens
    async with httpx.AsyncClient(timeout=10.0) as client:
        resp = await client.post(
            SPOTIFY_TOKEN_URL,
            data={
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": settings.SPOTIFY_REDIRECT_URI,
                "client_id": settings.SPOTIFY_CLIENT_ID,
                "client_secret": settings.SPOTIFY_CLIENT_SECRET,
            },
            headers={"Content-Type": "application/x-www-form-urlencoded"}
        )

    if resp.status_code != 200:
        raise HTTPException(status_code=400, detail=f"Spotify token exchange failed: {resp.text}")

    token_data = resp.json()
    access_token = token_data["access_token"]
    refresh_token = token_data.get("refresh_token", "")
    expires_in = token_data.get("expires_in", 3600)
    expires_at = datetime.utcnow() + timedelta(seconds=expires_in)

    # Get Spotify Profile ID
    async with httpx.AsyncClient(timeout=10.0) as client:
        profile_resp = await client.get(
            f"{SPOTIFY_API_BASE}/me",
            headers={"Authorization": f"Bearer {access_token}"}
        )
        spotify_id = profile_resp.json().get("id", "") if profile_resp.status_code == 200 else ""

    stmt = select(SpotifyAccount).where(SpotifyAccount.user_id == user.id)
    result = await db.execute(stmt)
    account = result.scalar_one_or_none()

    if not account:
        account = SpotifyAccount(
            user_id=user.id,
            spotify_id=spotify_id,
            access_token_enc=encrypt_value(access_token),
            refresh_token_enc=encrypt_value(refresh_token),
            expires_at=expires_at
        )
        db.add(account)
    else:
        account.spotify_id = spotify_id
        account.access_token_enc = encrypt_value(access_token)
        if refresh_token:
            account.refresh_token_enc = encrypt_value(refresh_token)
        account.expires_at = expires_at

    await db.commit()
    # Redirect cleanly to frontend UI
    return RedirectResponse(url="http://sync.nexus.link/?spotify_connected=true")

@router.get("/status")
async def spotify_connection_status(current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    stmt = select(SpotifyAccount).where(SpotifyAccount.user_id == current_user.id)
    res = await db.execute(stmt)
    account = res.scalar_one_or_none()
    return {
        "connected": account is not None,
        "spotify_id": account.spotify_id if account else None
    }

@router.get("/playlists", response_model=list[SpotifyPlaylistOut])
async def list_spotify_playlists(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    token = await get_valid_spotify_token(db, current_user.id)

    # Fetch playlists from Spotify API
    playlists_raw = []
    url = f"{SPOTIFY_API_BASE}/me/playlists?limit=50"
    async with httpx.AsyncClient(timeout=15.0) as client:
        while url:
            resp = await client.get(url, headers={"Authorization": f"Bearer {token}"})
            if resp.status_code != 200:
                break
            data = resp.json()
            playlists_raw.extend(data.get("items", []))
            url = data.get("next")

    # Fetch locally tracked playlist configs for this user
    stmt = select(Playlist).where(Playlist.owner_id == current_user.id)
    res = await db.execute(stmt)
    db_playlists = {p.spotify_playlist_id: p for p in res.scalars().all()}

    output: list[SpotifyPlaylistOut] = []
    for p in playlists_raw:
        if not p or not p.get("id"):
            continue
        sp_id = p["id"]
        name = p.get("name", "Untitled")
        images = p.get("images") or []
        cover_url = images[0]["url"] if images else None
        total_tracks = (p.get("tracks") or {}).get("total", 0)

        db_item = db_playlists.get(sp_id)
        if db_item:
            output.append(SpotifyPlaylistOut(
                id=sp_id,
                name=db_item.name,
                description=p.get("description"),
                cover_url=db_item.cover_url or cover_url,
                total_tracks=total_tracks,
                is_synced=db_item.is_synced,
                visibility=db_item.visibility,
                folder_slug=db_item.folder_slug,
                sync_status=db_item.sync_status,
                downloaded_tracks=db_item.downloaded_tracks,
                last_synced_at=db_item.last_synced_at
            ))
        else:
            output.append(SpotifyPlaylistOut(
                id=sp_id,
                name=name,
                description=p.get("description"),
                cover_url=cover_url,
                total_tracks=total_tracks,
                is_synced=False,
                visibility="private",
                folder_slug=slugify(name),
                sync_status="idle",
                downloaded_tracks=0,
                last_synced_at=None
            ))

    return output
