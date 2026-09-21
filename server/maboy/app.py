import asyncio
import hashlib
import hmac
import secrets
import uuid
from contextlib import asynccontextmanager
from typing import Annotated, Literal

from fastapi import Depends, FastAPI, Header, HTTPException, WebSocket, WebSocketDisconnect
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from .db import Base, engine, get_db
from .models import Operation, Playlist, PlaylistTrack, QueueItem, Token, Track, User

# In-memory routing only: audio bytes are never persisted on the gateway.
# A disconnected sender can reconnect; the receiver can retry indefinitely.
senders: dict[tuple[str, str], WebSocket] = {}
sender_available: dict[tuple[str, str], asyncio.Event] = {}
sender_locks: dict[tuple[str, str], asyncio.Lock] = {}
source_finished: dict[tuple[str, str], asyncio.Event] = {}


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
    kind: Literal["track.upsert", "playlist.upsert", "playlist.set_tracks", "queue.set"]
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


@app.websocket("/relay/{track_id}/source")
async def relay_source(ws: WebSocket, track_id: str, token: str, device: str, db: Session = Depends(get_db)):
    # Never take audio from a different account. This endpoint keeps no file bytes.
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
async def relay_receive(ws: WebSocket, track_id: str, token: str, db: Session = Depends(get_db)):
    key = relay_identity(db, token, track_id)
    if key is None:
        await ws.close(code=1008)
        return
    await ws.accept()
    try:
        while True:
            await sender_available.setdefault(key, asyncio.Event()).wait()
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


def apply_mutation(db: Session, user: User, mutation: Mutation):
    p = mutation.payload
    try:
        if mutation.kind == "track.upsert":
            item = Track(id=str(uuid.UUID(p["id"])), user_id=user.id, provider=str(p["provider"]),
                         source_id=str(p["source_id"]), title=str(p["title"]), artist=p.get("artist"))
            if not all((item.provider, item.source_id, item.title)):
                raise ValueError("Track fields cannot be empty")
            existing = db.get(Track, item.id)
            if existing:
                if existing.user_id != user.id or (existing.provider, existing.source_id) != (item.provider, item.source_id):
                    raise ValueError("Track identity cannot change")
                existing.title, existing.artist = item.title, item.artist
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
        elif mutation.kind == "playlist.set_tracks":
            playlist_id = str(uuid.UUID(p["playlist_id"]))
            ids = [str(uuid.UUID(i)) for i in p["track_ids"]]
            playlist = db.get(Playlist, playlist_id)
            if playlist is None or playlist.user_id != user.id or not unique_ids(ids):
                raise ValueError("Invalid playlist or duplicate tracks")
            if any(db.get(Track, i) is None or db.get(Track, i).user_id != user.id for i in ids):
                raise ValueError("Track not found")
            for old in db.scalars(select(PlaylistTrack).where(PlaylistTrack.playlist_id == playlist_id)).all():
                db.delete(old)
            db.flush()
            for index, track_id in enumerate(ids):
                db.add(PlaylistTrack(playlist_id=playlist_id, track_id=track_id, sort_key=index))
        elif mutation.kind == "queue.set":
            items = p["items"]
            ids = [str(uuid.UUID(item["id"])) for item in items]
            tracks = [str(uuid.UUID(item["track_id"])) for item in items]
            if not unique_ids(ids) or any(db.get(Track, i) is None or db.get(Track, i).user_id != user.id for i in tracks):
                raise ValueError("Invalid queue items or tracks")
            for old in db.scalars(select(QueueItem).where(QueueItem.user_id == user.id)).all():
                db.delete(old)
            db.flush()
            for index, (item_id, track_id) in enumerate(zip(ids, tracks)):
                db.add(QueueItem(id=item_id, user_id=user.id, track_id=track_id, sort_key=index))
    except (KeyError, TypeError, ValueError, AttributeError) as exc:
        raise HTTPException(422, f"Invalid mutation payload: {exc}") from exc


@app.post("/sync/operations")
def push(mutation: Mutation, user: User = Depends(current_user), db: Session = Depends(get_db)):
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
        raise HTTPException(409, "Conflicting operation or entity")
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