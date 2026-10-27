import os
import hashlib
import secrets
from datetime import datetime, timedelta
from pathlib import Path
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from jose import jwt, JWTError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
import httpx

from config import settings, encrypt_value, decrypt_value
from database import get_db
from models import User
from schemas import LoginRequest, TokenResponse, UserOut

router = APIRouter(prefix="/api/v1/auth", tags=["Authentication"])
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login")

def create_access_token(data: dict) -> str:
    to_encode = data.copy()
    expire = datetime.utcnow() + timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, settings.JWT_SECRET_KEY, algorithm=settings.JWT_ALGORITHM)

async def get_current_user(token: str = Depends(oauth2_scheme), db: AsyncSession = Depends(get_db)) -> User:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, settings.JWT_SECRET_KEY, algorithms=[settings.JWT_ALGORITHM])
        username: str = payload.get("username")
        if username is None:
            raise credentials_exception
    except JWTError:
        raise credentials_exception

    stmt = select(User).where(User.username == username)
    result = await db.execute(stmt)
    user = result.scalar_one_or_none()
    if user is None:
        raise credentials_exception
    return user

@router.post("/login", response_model=TokenResponse)
async def login(req: LoginRequest, db: AsyncSession = Depends(get_db)):
    navidrome_auth_url = f"{settings.NAVIDROME_URL}/auth/login"
    
    # 1. Authenticate with Navidrome Core API
    async with httpx.AsyncClient(timeout=10.0) as client:
        try:
            resp = await client.post(navidrome_auth_url, json={"username": req.username, "password": req.password})
        except Exception as e:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail=f"Navidrome service unreachable at {settings.NAVIDROME_URL}: {str(e)}"
            )

    if resp.status_code != 200:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid Navidrome username or password"
        )

    nav_data = resp.json()
    nav_id = nav_data.get("id") or str(nav_data.get("sub", ""))
    is_admin = bool(nav_data.get("isAdmin", False))

    # 2. Extract or Compute Subsonic Auth Credentials
    # Navidrome /auth/login returns subsonicToken and subsonicSalt if present; otherwise generate compatible auth token
    subsonic_token = nav_data.get("subsonicToken")
    subsonic_salt = nav_data.get("subsonicSalt")
    if not subsonic_token or not subsonic_salt:
        subsonic_salt = secrets.token_hex(6)
        subsonic_token = hashlib.md5((req.password + subsonic_salt).encode()).hexdigest()

    # 3. Upsert User in PostgreSQL
    stmt = select(User).where(User.username == req.username)
    result = await db.execute(stmt)
    user = result.scalar_one_or_none()

    if not user:
        user = User(
            username=req.username,
            navidrome_id=nav_id,
            is_admin=is_admin,
            subsonic_token_enc=encrypt_value(subsonic_token),
            subsonic_salt_enc=encrypt_value(subsonic_salt)
        )
        db.add(user)
    else:
        user.navidrome_id = nav_id
        user.is_admin = is_admin
        user.subsonic_token_enc = encrypt_value(subsonic_token)
        user.subsonic_salt_enc = encrypt_value(subsonic_salt)

    await db.commit()
    await db.refresh(user)

    # 4. Auto-Provision User's Private Directory on /mnt/audio_pool/music
    user_private_dir = Path(settings.MUSIC_ROOT) / "users" / req.username / "private"
    try:
        user_private_dir.mkdir(parents=True, exist_ok=True)
        os.chmod(user_private_dir, 0o775)
    except Exception as e:
        print(f"Warning: Could not set permissions on {user_private_dir}: {e}")

    # 5. Issue JWT Token
    jwt_token = create_access_token({
        "sub": user.id,
        "username": user.username,
        "is_admin": user.is_admin
    })

    return TokenResponse(
        access_token=jwt_token,
        token_type="bearer",
        username=user.username,
        is_admin=user.is_admin,
        navidrome_id=user.navidrome_id
    )

@router.get("/me", response_model=UserOut)
async def get_me(current_user: User = Depends(get_current_user)):
    return UserOut(
        id=current_user.id,
        username=current_user.username,
        is_admin=current_user.is_admin,
        created_at=current_user.created_at
    )
