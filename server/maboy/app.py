import asyncio
import hashlib
import hmac
import math
import secrets
import uuid
from contextlib import asynccontextmanager, contextmanager
from datetime import datetime
from typing import Annotated, Generator, Literal

from fastapi import Depends, FastAPI, Header, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from .db import Base, engine, get_db, SessionLocal
from . import friends as friends_api
from .models import FavoriteTrack, Operation, Playlist, PlaylistTrack, QueueItem, Token, Track, TrackShare, User
from .youtube_media import YouTubeDownloadError, ensure_youtube_audio

# In-memory routing only: audio bytes are never persisted on the gateway.
# A disconnected sender can reconnect; the receiver can retry indefinitely.
senders: dict[tuple[str, str], WebSocket] = {}
sender_available: dict[tuple[str, str], asyncio.Event] = {}
sender_locks: dict[tuple[str, str], asyncio.Lock] = {}
source_finished: dict[tuple[str, str], asyncio.Event] = {}
sync_clients: dict[str, dict[WebSocket, str]] = {}
device_disconnect_tasks: dict[tuple[str, str], asyncio.Task] = {}
DISCONNECT_GRACE_PERIOD: float = 10.0


async def prefetch_youtube_audio(source_id: str):
    try:
        await asyncio.to_thread(ensure_youtube_audio, source_id)
    except Exception:
        pass


@asynccontextmanager
async def lifespan(app: FastAPI):
    # MVP bootstrap; replace with versioned migrations before changing a deployed schema.
    Base.metadata.create_all(engine)
    with engine.begin() as connection:
        if connection.dialect.name == "sqlite":
            names = {row[1] for row in connection.exec_driver_sql("PRAGMA table_info(users)")}
            if "nickname" not in names:
                connection.exec_driver_sql("ALTER TABLE users ADD COLUMN nickname VARCHAR(40)")
        else:
            connection.exec_driver_sql(
                "ALTER TABLE users ADD COLUMN IF NOT EXISTS nickname VARCHAR(40)"
            )
        connection.exec_driver_sql(
            "CREATE UNIQUE INDEX IF NOT EXISTS ix_users_nickname ON users (nickname)"
        )
    with SessionLocal() as db:
        fav_count = db.scalar(select(func.count(FavoriteTrack.id)))
        if fav_count == 0:
            for user in db.scalars(select(User)).all():
                last_op = db.scalar(
                    select(Operation)
                    .where(Operation.user_id == user.id, Operation.kind == "favorites.set")
                    .order_by(Operation.version.desc())
                    .limit(1)
                )
                if last_op and isinstance(last_op.payload, dict) and "track_ids" in last_op.payload:
                    t_ids = last_op.payload.get("track_ids", [])
                    for idx, t_id in enumerate(t_ids):
                        if (t := db.get(Track, t_id)) and t.user_id == user.id:
                            db.add(FavoriteTrack(user_id=user.id, track_id=t_id, sort_key=idx))
            db.commit()
    yield


app = FastAPI(title="Maboy sync API", lifespan=lifespan)


class Credentials(BaseModel):
    email: EmailStr
    password: str = Field(min_length=12, max_length=256)


class Mutation(BaseModel):
    operation_id: uuid.UUID
    kind: Literal[
        "track.upsert", "track.set_order", "playlist.upsert", "playlist.delete", "playlist.set_tracks", "queue.set",
        "favorites.set", "history.add", "track.device_status",
        "equalizer.preset.upsert", "equalizer.preset.delete",
    ]
    payload: dict


def digest(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()


def password_hash(password: str, salt: bytes | None = None) -> str:
    salt = salt or secrets.token_bytes(16)
    return f"{salt.hex()}:{hashlib.scrypt(password.encode(), salt=salt, n=2**14, r=8, p=1).hex()}"


def authenticate(db: Session, credentials: Credentials) -> User | None:
    user = db.scalar(select(User).where(User.email == str(credentials.email).lower()))
    if user is None:
        return None
    salt, expected = user.password_hash.split(":")
    actual = password_hash(credentials.password, bytes.fromhex(salt)).split(":")[1]
    return user if hmac.compare_digest(expected, actual) else None


def issue_token(db: Session, user: User) -> dict:
    raw = secrets.token_urlsafe(32)
    db.add(Token(token_hash=digest(raw), user_id=user.id))
    db.commit()
    return {"access_token": raw, "token_type": "bearer"}


def current_user(authorization: Annotated[str | None, Header()] = None, db: Session = Depends(get_db)) -> User:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(401, "Bearer token required")
    token = db.get(Token, digest(authorization[7:]))
    user = db.get(User, token.user_id) if token else None
    if user is None:
        raise HTTPException(401, "Invalid token")
    return user


def relay_identity(db: Session, token: str, track_id: str) -> tuple[str, str] | None:
    credential = db.get(Token, digest(token))
    if credential is None:
        return None
    try:
        track = db.get(Track, str(uuid.UUID(track_id)))
    except ValueError:
        return None
    if track is None or track.provider not in ("local", "youtube"):
        return None
    if track.user_id == credential.user_id:
        return track.user_id, track.id
    share = db.scalar(select(TrackShare).where(
        TrackShare.status == "accepted",
        TrackShare.source_track_id == track.id,
        TrackShare.from_user_id == track.user_id,
        TrackShare.to_user_id == credential.user_id,
    ))
    if share is None:
        return None
    return track.user_id, track.id


def websocket_user(db: Session, token: str) -> User | None:
    credential = db.get(Token, digest(token))
    return db.get(User, credential.user_id) if credential else None


@contextmanager
def db_session() -> Generator[Session, None, None]:
    if get_db in app.dependency_overrides:
        gen = app.dependency_overrides[get_db]()
        try:
            yield next(gen)
        finally:
            gen.close()
    else:
        with SessionLocal() as db:
            yield db


def count_peer_devices(user_id: str, current_device_id: str = "", current_ws: WebSocket | None = None) -> int:
    other_devices = set()
    user_clients = sync_clients.get(user_id, {})
    for ws, dev_id in user_clients.items():
        if ws is current_ws:
            continue
        if dev_id:
            if not current_device_id or dev_id != current_device_id:
                other_devices.add(dev_id)
        else:
            other_devices.add(f"socket_{id(ws)}")
    for (uid, dev_id) in device_disconnect_tasks:
        if uid == user_id and dev_id and (not current_device_id or dev_id != current_device_id):
            other_devices.add(dev_id)
    return len(other_devices)


async def broadcast_presence(user_id: str):
    user_clients = sync_clients.get(user_id, {})
    for ws, dev_id in tuple(user_clients.items()):
        if not dev_id:
            continue
        peer_count = count_peer_devices(user_id, current_device_id=dev_id, current_ws=ws)
        try:
            await ws.send_json({"type": "presence", "peer_count": peer_count})
        except (WebSocketDisconnect, RuntimeError, OSError):
            user_clients.pop(ws, None)


@app.websocket("/sync/events")
async def sync_events(ws: WebSocket, token: str, device_id: str = "", device_name: str = ""):
    with db_session() as db:
        user = websocket_user(db, token)
        user_id = user.id if user else None
    if user_id is None:
        await ws.close(code=1008)
        return
    await ws.accept()

    if device_id:
        grace_task = device_disconnect_tasks.pop((user_id, device_id), None)
        if grace_task is not None and not grace_task.done():
            grace_task.cancel()

    clients = sync_clients.setdefault(user_id, {})
    clients[ws] = device_id
    await broadcast_presence(user_id)
    try:
        while True:
            # Client heartbeats also let the server notice a disconnected peer.
            await ws.receive_text()
    except (WebSocketDisconnect, RuntimeError, OSError):
        pass
    finally:
        clients.pop(ws, None)
        has_remaining = any(did == device_id for did in clients.values()) if device_id else False
        if device_id and not has_remaining:
            async def _grace_disconnect(uid: str, did: str):
                try:
                    await asyncio.sleep(DISCONNECT_GRACE_PERIOD)
                except asyncio.CancelledError:
                    return
                finally:
                    device_disconnect_tasks.pop((uid, did), None)
                await broadcast_presence(uid)

            device_disconnect_tasks[(user_id, device_id)] = asyncio.create_task(
                _grace_disconnect(user_id, device_id)
            )
        else:
            if not clients and not any(uid == user_id for uid, _ in device_disconnect_tasks):
                sync_clients.pop(user_id, None)
            await broadcast_presence(user_id)


async def announce_sync(user_id: str, version: int):
    clients_dict = sync_clients.get(user_id, {})
    for socket in tuple(clients_dict.keys()):
        try:
            await socket.send_json({"type": "changed", "version": version})
        except (WebSocketDisconnect, RuntimeError, OSError):
            clients_dict.pop(socket, None)


@app.websocket("/relay/{track_id}/source")
async def relay_source(ws: WebSocket, track_id: str, token: str, device: str):
    # Never take audio from a different account. This endpoint keeps no file bytes.
    with db_session() as db:
        key = relay_identity(db, token, track_id)
    if key is None:
        await ws.close(code=1008)
        return
    # Any device in the account that already has the complete file may seed it.
    # `device` is retained for diagnostics/protocol compatibility only.
    await ws.accept()
    if key in senders:
        await ws.close(code=1008)
        return
    senders[key] = ws
    finished = asyncio.Event()
    source_finished[key] = finished
    sender_available.setdefault(key, asyncio.Event()).set()
    try:
        # The receiver owns the read side while transferring.
        while not finished.is_set():
            try:
                await asyncio.wait_for(finished.wait(), timeout=15)
            except asyncio.TimeoutError:
                try:
                    await ws.send_text("ping")
                except (WebSocketDisconnect, RuntimeError, OSError):
                    break
    finally:
        if senders.get(key) is ws:
            senders.pop(key, None)
            sender_available[key].clear()
        if source_finished.get(key) is finished:
            source_finished.pop(key, None)


@app.websocket("/relay/{track_id}/receive")
async def relay_receive(ws: WebSocket, track_id: str, token: str, device: str = ""):
    with db_session() as db:
        key = relay_identity(db, token, track_id)
    if key is None:
        await ws.close(code=1008)
        return
    await ws.accept()
    user_id = key[0]
    if key not in senders:
        peers_available = count_peer_devices(user_id, current_device_id=device, current_ws=ws)
        if peers_available == 0:
            try:
                await ws.send_text("peer_offline")
            except (WebSocketDisconnect, RuntimeError, OSError):
                pass
            await ws.close()
            return

        for client, dev_id in tuple(sync_clients.get(user_id, {}).items()):
            if client != ws and (not device or dev_id != device):
                try:
                    await client.send_json({"type": "relay_request", "track_id": track_id})
                except (WebSocketDisconnect, RuntimeError, OSError):
                    sync_clients.get(user_id, {}).pop(client, None)
    try:
        while True:
            try:
                await asyncio.wait_for(sender_available.setdefault(key, asyncio.Event()).wait(), timeout=30.0)
            except asyncio.TimeoutError:
                try:
                    await ws.send_text("retry")
                except (WebSocketDisconnect, RuntimeError, OSError):
                    pass
                return
            async with sender_locks.setdefault(key, asyncio.Lock()):
                source = senders.get(key)
                if source is None:
                    continue
                try:
                    await source.send_json({"type": "send", "track_id": track_id})
                    while True:
                        message = await source.receive()
                        if message.get("type") == "websocket.disconnect":
                            raise WebSocketDisconnect()
                        if message.get("bytes") is not None:
                            await ws.send_bytes(message["bytes"])
                        elif message.get("text") == "done":
                            await ws.send_text("done")
                            source_finished[key].set()
                            return
                        else:
                            raise WebSocketDisconnect()
                except (WebSocketDisconnect, RuntimeError, OSError):
                    if senders.get(key) is source:
                        senders.pop(key, None)
                        sender_available[key].clear()
                        source_finished[key].set()
                    # A failed transfer must be restarted from byte zero by the client.
                    try:
                        await ws.send_text("retry")
                    except (WebSocketDisconnect, RuntimeError, OSError):
                        return
    except (WebSocketDisconnect, RuntimeError, OSError):
        pass


@app.post("/auth/register", status_code=201)
def register(credentials: Credentials, db: Session = Depends(get_db)):
    user = User(email=str(credentials.email).lower(), password_hash=password_hash(credentials.password))
    db.add(user)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(409, "Email already registered")
    return issue_token(db, user)


@app.post("/auth/login")
def login(credentials: Credentials, db: Session = Depends(get_db)):
    user = authenticate(db, credentials)
    if user is None:
        raise HTTPException(401, "Invalid credentials")
    return issue_token(db, user)


def unique_ids(ids: list[str]) -> bool:
    return len(ids) == len(set(ids))


def normalize_equalizer_mutation(mutation: Mutation) -> None:
    """Canonicalize synced presets and drop every device-local field."""
    p = mutation.payload
    if mutation.kind == "equalizer.preset.upsert":
        preset_id = str(uuid.UUID(p["id"]))
        name = str(p["name"]).strip()
        gains = p["gains"]
        if not 1 <= len(name) <= 40 or not isinstance(gains, list) or len(gains) != 6:
            raise ValueError("Invalid equalizer preset")
        normalized_gains = [float(gain) for gain in gains]
        if any(not math.isfinite(gain) or gain < -12 or gain > 12 for gain in normalized_gains):
            raise ValueError("Equalizer gains must be finite values from -12 to +12 dB")
        p.clear()
        p.update({"id": preset_id, "name": name, "gains": normalized_gains})
    elif mutation.kind == "equalizer.preset.delete":
        preset_id = str(uuid.UUID(p["id"]))
        p.clear()
        p.update({"id": preset_id})


def apply_mutation(db: Session, user: User, mutation: Mutation):
    p = mutation.payload
    try:
        if mutation.kind == "track.upsert":
            item = Track(id=str(uuid.UUID(p["id"])), user_id=user.id, provider=str(p["provider"]),
                         source_id=str(p["source_id"]), title=str(p["title"]), artist=p.get("artist"))
            if not all((item.provider, item.source_id, item.title)):
                raise ValueError("Track fields cannot be empty")
            if item.provider == "local" and not item.source_id.endswith(item.id):
                item.source_id = f"{item.source_id}:{item.id}"
            existing = db.get(Track, item.id)
            if existing:
                if existing.user_id != user.id:
                    raise ValueError("Track not found")
                existing.title, existing.artist = item.title, item.artist
            else:
                existing_source = None
                if item.provider != "local":
                    existing_source = db.scalar(
                        select(Track).where(
                            Track.user_id == user.id,
                            Track.provider == item.provider,
                            Track.source_id == item.source_id,
                        )
                    )
                if existing_source:
                    existing_source.title, existing_source.artist = item.title, item.artist
                else:
                    db.add(item)
        elif mutation.kind == "track.set_order":
            ids = [str(uuid.UUID(track_id)) for track_id in p["track_ids"]]
            if not unique_ids(ids):
                raise ValueError("Duplicate tracks in order")
            if any((track := db.get(Track, track_id)) is None or track.user_id != user.id for track_id in ids):
                raise ValueError("Invalid track order")
        elif mutation.kind == "playlist.upsert":
            item_id = str(uuid.UUID(p["id"]))
            name = str(p["name"]).strip()
            sort_key = int(p["sort_key"])
            if not name or sort_key < 0:
                raise ValueError("Invalid playlist")
            item = db.get(Playlist, item_id)
            if item:
                if item.user_id != user.id:
                    raise ValueError("Playlist not found")
                item.name, item.sort_key = name, sort_key
            else:
                db.add(Playlist(id=item_id, user_id=user.id, name=name, sort_key=sort_key))
        elif mutation.kind == "playlist.delete":
            playlist_id = str(uuid.UUID(p["id"]))
            playlist = db.get(Playlist, playlist_id)
            if playlist is None or playlist.user_id != user.id:
                raise ValueError("Playlist not found")
            for old in db.scalars(select(PlaylistTrack).where(PlaylistTrack.playlist_id == playlist_id)).all():
                db.delete(old)
            db.delete(playlist)
        elif mutation.kind == "playlist.set_tracks":
            playlist_id = str(uuid.UUID(p["playlist_id"]))
            ids = [str(uuid.UUID(i)) for i in p["track_ids"]]
            playlist = db.get(Playlist, playlist_id)
            if playlist is None or playlist.user_id != user.id or not unique_ids(ids):
                raise ValueError("Invalid playlist or duplicate tracks")
            if any(db.get(Track, i) is not None and db.get(Track, i).user_id != user.id for i in ids):
                raise ValueError("Access denied to tracks of another user")
            valid_ids = [i for i in ids if (t := db.get(Track, i)) and t.user_id == user.id]
            for old in db.scalars(select(PlaylistTrack).where(PlaylistTrack.playlist_id == playlist_id)).all():
                db.delete(old)
            db.flush()
            for index, track_id in enumerate(valid_ids):
                db.add(PlaylistTrack(playlist_id=playlist_id, track_id=track_id, sort_key=index))
        elif mutation.kind == "queue.set":
            items = p["items"]
            ids = [str(uuid.UUID(item["id"])) for item in items]
            tracks = [str(uuid.UUID(item["track_id"])) for item in items]
            if not unique_ids(ids):
                raise ValueError("Duplicate queue items")
            if any(db.get(Track, i) is not None and db.get(Track, i).user_id != user.id for i in tracks):
                raise ValueError("Access denied to tracks of another user")
            valid_pairs = [
                (item_id, track_id)
                for item_id, track_id in zip(ids, tracks)
                if (t := db.get(Track, track_id)) and t.user_id == user.id
            ]
            for old in db.scalars(select(QueueItem).where(QueueItem.user_id == user.id)).all():
                db.delete(old)
            db.flush()
            for index, (item_id, track_id) in enumerate(valid_pairs):
                db.add(QueueItem(id=item_id, user_id=user.id, track_id=track_id, sort_key=index))
        elif mutation.kind == "favorites.set":
            track_ids = [str(uuid.UUID(item)) for item in p["track_ids"]]
            if len(track_ids) != len(set(track_ids)):
                raise ValueError("Duplicate favorite tracks")
            if any(db.get(Track, item) is not None and db.get(Track, item).user_id != user.id for item in track_ids):
                raise ValueError("Access denied to tracks of another user")
            valid_incoming = [
                t_id for t_id in track_ids
                if (t := db.get(Track, t_id)) and t.user_id == user.id
            ]
            existing_rows = db.scalars(
                select(FavoriteTrack)
                .where(FavoriteTrack.user_id == user.id)
                .order_by(FavoriteTrack.sort_key)
            ).all()
            existing_ids = [r.track_id for r in existing_rows]

            added = [t for t in valid_incoming if t not in existing_ids]
            removed = set(existing_ids) - set(valid_incoming)

            if added:
                merged_ids = existing_ids + added
            elif len(removed) == 1:
                removed_id = next(iter(removed))
                merged_ids = [t for t in existing_ids if t != removed_id]
            elif not valid_incoming and len(existing_ids) <= 1:
                merged_ids = []
            else:
                merged_ids = existing_ids

            mutation.payload["track_ids"] = merged_ids

            for old in existing_rows:
                db.delete(old)
            db.flush()
            for index, t_id in enumerate(merged_ids):
                db.add(FavoriteTrack(user_id=user.id, track_id=t_id, sort_key=index))

            for t_id in added:
                t = db.get(Track, t_id)
                if t and t.provider == "youtube" and t.source_id:
                    try:
                        asyncio.create_task(prefetch_youtube_audio(t.source_id))
                    except RuntimeError:
                        pass
        elif mutation.kind == "track.device_status":
            str(uuid.UUID(p["track_id"]))
            if not str(p.get("device_id", "")).strip():
                raise ValueError("Invalid device_id")
        elif mutation.kind == "history.add":
            str(uuid.UUID(p["id"]))
            track_id = str(uuid.UUID(p["track_id"]))
            started_at = datetime.fromisoformat(p["started_at"].replace("Z", "+00:00"))
            if (
                db.get(Track, track_id) is None
                or db.get(Track, track_id).user_id != user.id
                or started_at.tzinfo is None
                or not isinstance(p["completed"], bool)
                or not str(p["device_id"]).strip()
            ):
                raise ValueError("Invalid history entry")
        elif mutation.kind.startswith("equalizer.preset."):
            normalize_equalizer_mutation(mutation)
        else:
            raise ValueError("Unsupported mutation kind")
    except (KeyError, TypeError, ValueError, AttributeError) as exc:
        raise HTTPException(422, f"Invalid mutation payload: {exc}") from exc


@app.post("/sync/operations")
async def push(mutation: Mutation, user: User = Depends(current_user), db: Session = Depends(get_db)):
    if mutation.kind.startswith("equalizer.preset."):
        try:
            normalize_equalizer_mutation(mutation)
        except (KeyError, TypeError, ValueError, AttributeError) as exc:
            raise HTTPException(422, f"Invalid mutation payload: {exc}") from exc
    # Lock before checking the operation ID: two simultaneous retries must not apply twice.
    user = db.scalar(select(User).where(User.id == user.id).with_for_update())
    existing = db.scalar(select(Operation).where(Operation.user_id == user.id,
                                                 Operation.operation_id == str(mutation.operation_id)))
    if existing:
        if existing.kind != mutation.kind or existing.payload != mutation.payload:
            raise HTTPException(409, "Operation ID reused with different content")
        return {"version": existing.version, "duplicate": True}
    apply_mutation(db, user, mutation)
    user.version += 1
    db.add(Operation(user_id=user.id, operation_id=str(mutation.operation_id),
                     kind=mutation.kind, payload=mutation.payload, version=user.version))
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        existing_op = db.scalar(
            select(Operation).where(
                Operation.user_id == user.id,
                Operation.operation_id == str(mutation.operation_id),
            )
        )
        if existing_op:
            return {"version": existing_op.version, "duplicate": True}
        raise HTTPException(409, "Conflicting operation or entity")
    await announce_sync(user.id, user.version)
    return {"version": user.version, "duplicate": False}


@app.get("/sync/operations")
def pull(after: int = 0, limit: int = 100, user: User = Depends(current_user), db: Session = Depends(get_db)):
    if after < 0 or not 1 <= limit <= 500:
        raise HTTPException(422, "Invalid cursor or limit")
    ops = db.scalars(select(Operation).where(Operation.user_id == user.id, Operation.version > after)
                     .order_by(Operation.version).limit(limit)).all()
    return {"operations": [{"operation_id": op.operation_id, "version": op.version,
                             "kind": op.kind, "payload": op.payload} for op in ops],
            "cursor": ops[-1].version if ops else after}


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/youtube/tracks/{track_id}/audio")
async def youtube_audio(
    track_id: str,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    try:
        normalized_id = str(uuid.UUID(track_id))
    except ValueError as exc:
        raise HTTPException(404, "Track not found") from exc
    track = db.get(Track, normalized_id)
    if track is None or track.user_id != user.id or track.provider != "youtube":
        raise HTTPException(404, "Track not found")
    try:
        audio_file = await ensure_youtube_audio(track.source_id)
    except YouTubeDownloadError as exc:
        raise HTTPException(503, str(exc)) from exc
    return FileResponse(
        audio_file,
        media_type="audio/mpeg",
        filename=f"{track.id}.mp3",
    )


@app.put("/account/nickname")
def set_nickname(body: friends_api.NicknameIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return friends_api.set_nickname(db, user, body.nickname)


@app.get("/friends")
def list_friends(user: User = Depends(current_user), db: Session = Depends(get_db)):
    return friends_api.snapshot(db, user)


@app.post("/friends/requests", status_code=201)
def request_friend(body: friends_api.NicknameIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return friends_api.request_friend(db, user, body.nickname)


@app.post("/friends/requests/{request_id}/accept")
def accept_friend(request_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return friends_api.accept_request(db, user, request_id)


@app.post("/friends/{nickname}/shares", status_code=201)
def share_track(nickname: str, body: friends_api.ShareIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return friends_api.share_track(db, user, nickname, body.track_id)


@app.post("/friends/shares/{share_id}/accept")
def accept_share(share_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return friends_api.accept_share(db, user, share_id)


@app.get("/friends/shares/{share_id}/file")
def shared_file(share_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    track_id = friends_api.shared_file(db, user, share_id)
    path = audio_path(track_id)
    if not path.is_file():
        raise HTTPException(404, "file_not_uploaded")
    return FileResponse(path, media_type="audio/mpeg", filename=f"{track_id}.mp3")

