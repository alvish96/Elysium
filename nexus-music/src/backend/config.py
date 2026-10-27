import base64
import hashlib
from pydantic_settings import BaseSettings
from cryptography.fernet import Fernet

class Settings(BaseSettings):
    POSTGRES_USER: str = "nexussync"
    POSTGRES_PASSWORD: str = "nexus_sync_db_pass_change_me"
    POSTGRES_DB: str = "nexussync"
    POSTGRES_HOST: str = "nexus-sync-postgres-svc.media.svc.cluster.local"
    POSTGRES_PORT: int = 5432

    REDIS_HOST: str = "nexus-sync-redis-svc.media.svc.cluster.local"
    REDIS_PORT: int = 6379

    JWT_SECRET_KEY: str = "super_secret_jwt_signing_key_change_me"
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24 * 7  # 7 days

    FERNET_KEY: str = "MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY="

    SPOTIFY_CLIENT_ID: str = ""
    SPOTIFY_CLIENT_SECRET: str = ""
    SPOTIFY_REDIRECT_URI: str = "http://sync.nexus.link/api/v1/spotify/callback"

    NAVIDROME_URL: str = "http://navidrome-svc.media.svc.cluster.local:4533"
    MUSIC_ROOT: str = "/mnt/audio_pool/music"

    class Config:
        env_file = ".env"
        extra = "ignore"

settings = Settings()

def get_fernet() -> Fernet:
    # Ensure 32-byte url-safe base64 key even if a raw secret string is provided
    digest = hashlib.sha256(settings.FERNET_KEY.encode()).digest()
    url_safe_key = base64.urlsafe_b64encode(digest)
    return Fernet(url_safe_key)

def encrypt_value(raw: str) -> str:
    if not raw:
        return ""
    return get_fernet().encrypt(raw.encode()).decode()

def decrypt_value(token: str) -> str:
    if not token:
        return ""
    try:
        return get_fernet().decrypt(token.encode()).decode()
    except Exception:
        return ""
