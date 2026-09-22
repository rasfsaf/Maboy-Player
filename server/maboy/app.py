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
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from .db import Base, engine, get_db, SessionLocal
from .models import Operation, Playlist, PlaylistTrack, QueueItem, Token, Track, User

# In-memory routing only: audio bytes are never persisted on the gateway.
# A disconnected sender can reconnect; the receiver can retry indefinitely.
senders: dict[tuple[str, str], WebSocket] = {}
sender_available: dict[tuple[str, str], asyncio.Event] = {}
sender_locks: dict[tuple[str, str], asyncio.Lock] = {}
source_finished: dict[tuple[str, str], asyncio.Event] = {}
sync_clients: dict[str, set[WebSocket]] = {}


@asynccontextmanager
async def lifespan(app: FastAPI):
    # MVP bootstrap; replace with versioned migrations before changing a deployed schema.
    Base.metadata.create_all(engine)
    yield


app = FastAPI(title="Maboy sync API", lifespan=lifespan)


class Credentials(BaseModel):
    email: EmailStr
    password: str = Field(min_length=12, max_length=256)


class Mutation(BaseModel):
    operation_id: uuid.UUID
    kind: Literal[
        "track.upsert", "playlist.upsert", "playlist.delete", "playlist.set_tracks", "queue.set",
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
    if track is None or track.user_id != credential.user_id or track.provider != "local":
        return None
    return credential.user_id, track.id


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


@app.websocket("/sync/events")
async def sync_events(ws: WebSocket, token: str):
    with db_session() as db:
        user = websocket_user(db, token)
        user_id = user.id if user else None
    if user_id is None:
        await ws.close(code=1008)
        return
    await ws.accept()
    clients = sync_clients.setdefault(user_id, set())
    clients.add(ws)
    try:
        while True:
            # Client heartbeats also let the server notice a disconnected peer.
            await ws.receive_text()
    except (WebSocketDisconnect, RuntimeError, OSError):
        pass
    finally:
        clients.discard(ws)
        if not clients:
            sync_clients.pop(user_id, None)


async def announce_sync(user_id: str, version: int):
    for socket in tuple(sync_clients.get(user_id, ())):
        try:
            await socket.send_json({"type": "changed", "version": version})
        except (WebSocketDisconnect, RuntimeError, OSError):
            sync_clients.get(user_id, set()).discard(socket)


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
async def relay_receive(ws: WebSocket, track_id: str, token: str):
    with db_session() as db:
        key = relay_identity(db, token, track_id)
    if key is None:
        await ws.close(code=1008)
        return
    await ws.accept()
    user_id = key[0]
    if key not in senders:
        for client in tuple(sync_clients.get(user_id, ())):
            try:
                await client.send_json({"type": "relay_request", "track_id": track_id})
            except (WebSocketDisconnect, RuntimeError, OSError):
                sync_clients.get(user_id, set()).discard(client)
    try:
        while True:
            try:
                await asyncio.wait_for(sender_available.setdefault(key, asyncio.Event()).wait(), timeout=10.0)
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
