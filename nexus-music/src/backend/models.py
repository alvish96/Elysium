import uuid
from datetime import datetime
from sqlalchemy import Column, String, Boolean, DateTime, Integer, ForeignKey, Text
from sqlalchemy.orm import relationship
from database import Base

class User(Base):
    __tablename__ = "users"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    username = Column(String(64), unique=True, nullable=False, index=True)
    is_admin = Column(Boolean, default=False, nullable=False)
    navidrome_id = Column(String(64), nullable=True)
    subsonic_token_enc = Column(Text, nullable=True)
    subsonic_salt_enc = Column(Text, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    spotify_account = relationship("SpotifyAccount", back_populates="user", uselist=False, cascade="all, delete-orphan")
    playlists = relationship("Playlist", back_populates="owner", cascade="all, delete-orphan")

class SpotifyAccount(Base):
    __tablename__ = "spotify_accounts"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(String(36), ForeignKey("users.id", ondelete="CASCADE"), unique=True, nullable=False)
    spotify_id = Column(String(64), nullable=True)
    access_token_enc = Column(Text, nullable=False)
    refresh_token_enc = Column(Text, nullable=False)
    expires_at = Column(DateTime, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    user = relationship("User", back_populates="spotify_account")

class Playlist(Base):
    __tablename__ = "playlists"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    spotify_playlist_id = Column(String(64), nullable=False, index=True)
    owner_id = Column(String(36), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    name = Column(String(255), nullable=False)
    folder_slug = Column(String(255), nullable=False)
    cover_url = Column(Text, nullable=True)
    total_tracks = Column(Integer, default=0, nullable=False)
    downloaded_tracks = Column(Integer, default=0, nullable=False)
    is_synced = Column(Boolean, default=False, nullable=False)
    is_imported = Column(Boolean, default=False, nullable=False)
    visibility = Column(String(16), default="private", nullable=False)  # 'private' or 'public'
    sync_status = Column(String(32), default="idle", nullable=False)   # 'idle', 'queued', 'syncing', 'completed', 'failed'
    last_synced_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    owner = relationship("User", back_populates="playlists")
    tracks = relationship("PlaylistTrack", back_populates="playlist", cascade="all, delete-orphan")

class Track(Base):
    __tablename__ = "tracks"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    spotify_track_id = Column(String(64), unique=True, nullable=False, index=True)
    title = Column(String(255), nullable=False)
    artist = Column(String(255), nullable=False)
    album = Column(String(255), nullable=True)
    duration_ms = Column(Integer, default=0, nullable=False)
    cover_url = Column(Text, nullable=True)
    file_path = Column(Text, nullable=False)
    download_status = Column(String(32), default="downloaded", nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    playlists = relationship("PlaylistTrack", back_populates="track", cascade="all, delete-orphan")

class PlaylistTrack(Base):
    __tablename__ = "playlist_tracks"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    playlist_id = Column(String(36), ForeignKey("playlists.id", ondelete="CASCADE"), nullable=False)
    track_id = Column(String(36), ForeignKey("tracks.id", ondelete="CASCADE"), nullable=False)
    position = Column(Integer, default=0, nullable=False)

    playlist = relationship("Playlist", back_populates="tracks")
    track = relationship("Track", back_populates="playlists")
