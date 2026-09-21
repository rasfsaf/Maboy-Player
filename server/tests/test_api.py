import uuid

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from maboy.app import app
from maboy.db import Base, get_db


@pytest.fixture
def client():
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    Base.metadata.create_all(engine)
    session_factory = sessionmaker(bind=engine)

    def db_override():
        with session_factory() as session:
            yield session

    app.dependency_overrides[get_db] = db_override
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()
    engine.dispose()


def register(client, email):
    response = client.post("/auth/register", json={"email": email, "password": "long-password-123"})
    assert response.status_code == 201, response.text
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def send(client, headers, kind, payload, operation_id=None):
    return client.post("/sync/operations", headers=headers,
                       json={"operation_id": operation_id or str(uuid.uuid4()), "kind": kind, "payload": payload})


def test_auth_and_isolation(client):
    alice = register(client, "Alice@example.com")
    bob = register(client, "bob@example.com")
    assert client.post("/auth/register", json={"email": "alice@example.com", "password": "long-password-123"}).status_code == 409
    assert client.post("/auth/login", json={"email": "alice@example.com", "password": "wrong-password"}).status_code == 401
    assert client.post("/auth/login", json={"email": "alice@example.com", "password": "long-password-123"}).status_code == 200
    track_id = str(uuid.uuid4())
    assert send(client, alice, "track.upsert", {"id": track_id, "provider": "youtube", "source_id": "vid1", "title": "Song"}).status_code == 200
    assert client.get("/sync/operations", headers=bob).json()["operations"] == []
    assert send(client, bob, "queue.set", {"items": [{"id": str(uuid.uuid4()), "track_id": track_id}]}).status_code == 422
    assert client.get("/sync/operations").status_code == 401


def test_idempotency_and_cursor(client):
    auth = register(client, "a@example.com")
    op_id, track_id = str(uuid.uuid4()), str(uuid.uuid4())
    payload = {"id": track_id, "provider": "youtube", "source_id": "one", "title": "One"}
    assert send(client, auth, "track.upsert", payload, op_id).json() == {"version": 1, "duplicate": False}
    assert send(client, auth, "track.upsert", payload, op_id).json() == {"version": 1, "duplicate": True}
    assert send(client, auth, "track.upsert", {**payload, "title": "Two"}, op_id).status_code == 409
    assert send(client, auth, "track.upsert", {**payload, "title": "Two"}).json()["version"] == 2
    page = client.get("/sync/operations?limit=1", headers=auth).json()
    assert page["cursor"] == 1 and len(page["operations"]) == 1
    assert client.get("/sync/operations?after=1", headers=auth).json()["operations"][0]["version"] == 2


def test_playlist_and_queue_order(client):
    auth = register(client, "a@example.com")
    tracks = [str(uuid.uuid4()), str(uuid.uuid4())]
    for index, track_id in enumerate(tracks):
        assert send(client, auth, "track.upsert", {"id": track_id, "provider": "youtube", "source_id": str(index), "title": str(index)}).status_code == 200
    playlist = str(uuid.uuid4())
    assert send(client, auth, "playlist.upsert", {"id": playlist, "name": "Favorites", "sort_key": 0}).status_code == 200
    assert send(client, auth, "playlist.set_tracks", {"playlist_id": playlist, "track_ids": tracks[::-1]}).status_code == 200
    assert send(client, auth, "playlist.set_tracks", {"playlist_id": playlist, "track_ids": tracks}).status_code == 200
    assert send(client, auth, "playlist.set_tracks", {"playlist_id": playlist, "track_ids": tracks * 2}).status_code == 422
    items = [{"id": str(uuid.uuid4()), "track_id": track} for track in tracks + tracks[:1]]
    assert send(client, auth, "queue.set", {"items": items}).status_code == 200
    assert send(client, auth, "queue.set", {"items": items[::-1]}).status_code == 200
    from maboy.models import PlaylistTrack, QueueItem
    from sqlalchemy import select
    # Read the database via the same overridden session used by the API.
    session_generator = app.dependency_overrides[get_db]()
    try:
        db = next(session_generator)
        playlist_tracks = db.scalars(select(PlaylistTrack).order_by(PlaylistTrack.sort_key)).all()
        queue = db.scalars(select(QueueItem).order_by(QueueItem.sort_key)).all()
        assert [entry.track_id for entry in playlist_tracks] == tracks
        assert [entry.id for entry in queue] == [entry["id"] for entry in items[::-1]]
    finally:
        session_generator.close()


def test_invalid_mutation_does_not_increment_version(client):
    auth = register(client, "a@example.com")
    assert send(client, auth, "playlist.set_tracks", {"playlist_id": str(uuid.uuid4()), "track_ids": []}).status_code == 422
    assert client.get("/sync/operations", headers=auth).json() == {"operations": [], "cursor": 0}


def test_local_track_sync_contains_metadata_but_no_audio(client):
    auth = register(client, "local@example.com")
    track_id = str(uuid.uuid4())
    payload = {"id": track_id, "provider": "local", "source_id": "phone-1",
               "title": "song.flac", "artist": None}
    assert send(client, auth, "track.upsert", payload).status_code == 200
    operation = client.get("/sync/operations", headers=auth).json()["operations"][0]
    assert operation["payload"] == payload
    assert not ({"bytes", "path", "content"} & operation["payload"].keys())


def test_relay_is_restricted_to_track_owner(client):
    owner = register(client, "relay-owner@example.com")
    stranger = register(client, "relay-stranger@example.com")
    track_id = str(uuid.uuid4())
    assert send(client, owner, "track.upsert", {
        "id": track_id, "provider": "local", "source_id": "phone",
        "title": "private.mp3", "artist": None,
    }).status_code == 200
    stranger_token = stranger["Authorization"].removeprefix("Bearer ")
    with pytest.raises(Exception):
        with client.websocket_connect(f"/relay/{track_id}/receive?token={stranger_token}"):
            pass