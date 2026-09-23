import uuid
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from maboy.app import app
from maboy.db import Base, get_db
from maboy.youtube_media import _classify_failure


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


def test_track_order_sync_and_account_isolation(client):
    alice = register(client, "order-owner@example.com")
    bob = register(client, "order-other@example.com")
    ids = [str(uuid.uuid4()), str(uuid.uuid4())]
    for index, track_id in enumerate(ids):
        assert send(client, alice, "track.upsert", {
            "id": track_id, "provider": "youtube",
            "source_id": f"order-video-{index}", "title": f"Track {index}",
        }).status_code == 200
    response = send(client, alice, "track.set_order", {"track_ids": ids[::-1]})
    assert response.status_code == 200, response.text
    operations = client.get("/sync/operations", headers=alice).json()["operations"]
    assert operations[-1]["kind"] == "track.set_order"
    assert operations[-1]["payload"]["track_ids"] == ids[::-1]
    assert send(client, bob, "track.set_order", {"track_ids": ids}).status_code == 422
    assert send(client, alice, "track.set_order", {"track_ids": ids * 2}).status_code == 422


def test_youtube_audio_is_cached_server_side_and_account_isolated(
    client, monkeypatch, tmp_path
):
    alice = register(client, "youtube-owner@example.com")
    bob = register(client, "youtube-stranger@example.com")
    track_id = str(uuid.uuid4())
    assert send(
        client,
        alice,
        "track.upsert",
        {
            "id": track_id,
            "provider": "youtube",
            "source_id": "6fCpJGnEJCY",
            "title": "Song",
        },
    ).status_code == 200

    audio_file = tmp_path / "cached.mp3"
    audio_file.write_bytes(b"ID3" + b"audio" * 2_000)
    calls = []

    async def fake_download(video_id):
        calls.append(video_id)
        return Path(audio_file)

    monkeypatch.setattr("maboy.app.ensure_youtube_audio", fake_download)
    response = client.get(f"/youtube/tracks/{track_id}/audio", headers=alice)
    assert response.status_code == 200
    assert response.headers["content-type"].startswith("audio/mpeg")
    assert response.content == audio_file.read_bytes()
    assert calls == ["6fCpJGnEJCY"]
    assert client.get(
        f"/youtube/tracks/{track_id}/audio", headers=bob
    ).status_code == 404


def test_server_youtube_cookie_failure_is_actionable():
    assert _classify_failure(
        "The provided YouTube account cookies are no longer valid and rotated"
    ) == "Серверные cookies YouTube устарели"


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


def test_playlist_can_be_deleted(client):
    auth = register(client, "delete-playlist@example.com")
    track_id = str(uuid.uuid4())
    playlist_id = str(uuid.uuid4())
    assert send(client, auth, "track.upsert", {
        "id": track_id, "provider": "youtube", "source_id": "delete-me", "title": "Song",
    }).status_code == 200
    assert send(client, auth, "playlist.upsert", {
        "id": playlist_id, "name": "Temporary", "sort_key": 0,
    }).status_code == 200
    assert send(client, auth, "playlist.set_tracks", {
        "playlist_id": playlist_id, "track_ids": [track_id],
    }).status_code == 200
    assert send(client, auth, "playlist.delete", {"id": playlist_id}).status_code == 200
    assert send(client, auth, "playlist.delete", {"id": playlist_id}).status_code == 422

    from maboy.models import Playlist, PlaylistTrack
    session_generator = app.dependency_overrides[get_db]()
    try:
        db = next(session_generator)
        assert db.get(Playlist, playlist_id) is None
        assert db.query(PlaylistTrack).filter_by(playlist_id=playlist_id).count() == 0
    finally:
        session_generator.close()


def test_sync_websocket_announces_committed_version(client):
    auth = register(client, "realtime@example.com")
    token = auth["Authorization"].removeprefix("Bearer ")
    with client.websocket_connect(f"/sync/events?token={token}") as socket:
        track_id = str(uuid.uuid4())
        response = send(client, auth, "track.upsert", {
            "id": track_id, "provider": "youtube", "source_id": "realtime", "title": "Realtime",
        })
        assert response.status_code == 200
        assert socket.receive_json() == {"type": "changed", "version": 1}


def test_sync_websocket_rejects_invalid_token(client):
    with pytest.raises(Exception):
        with client.websocket_connect("/sync/events?token=invalid"):
            pass


def test_invalid_mutation_does_not_increment_version(client):
    auth = register(client, "a@example.com")
    assert send(client, auth, "playlist.set_tracks", {"playlist_id": str(uuid.uuid4()), "track_ids": []}).status_code == 422
    assert client.get("/sync/operations", headers=auth).json() == {"operations": [], "cursor": 0}


def test_favorites_and_history_are_validated_and_synced(client):
    owner = register(client, "library@example.com")
    stranger = register(client, "library-stranger@example.com")
    track_id = str(uuid.uuid4())
    assert send(client, owner, "track.upsert", {
        "id": track_id, "provider": "local", "source_id": "library-track", "title": "Song",
    }).status_code == 200

    assert send(client, owner, "favorites.set", {"track_ids": [track_id]}).status_code == 200
    assert send(client, owner, "favorites.set", {"track_ids": [track_id, track_id]}).status_code == 422
    assert send(client, stranger, "favorites.set", {"track_ids": [track_id]}).status_code == 422

    history = {
        "id": str(uuid.uuid4()), "track_id": track_id,
        "started_at": "2026-09-21T12:00:00Z", "completed": False, "device_id": "test-device",
    }
    assert send(client, owner, "history.add", history).status_code == 200
    assert send(client, stranger, "history.add", history).status_code == 422
    operations = client.get("/sync/operations", headers=owner).json()["operations"]
    assert [operation["kind"] for operation in operations] == [
        "track.upsert", "favorites.set", "history.add",
    ]
    assert operations[-1]["payload"] == history


def test_local_track_sync_contains_metadata_but_no_audio(client):
    auth = register(client, "local@example.com")
    track_id = str(uuid.uuid4())
    payload = {"id": track_id, "provider": "local", "source_id": "phone-1",
               "title": "song.flac", "artist": None}
    assert send(client, auth, "track.upsert", payload).status_code == 200
    operation = client.get("/sync/operations", headers=auth).json()["operations"][0]
    assert operation["payload"] == payload
    assert not ({"bytes", "path", "content"} & operation["payload"].keys())


def test_equalizer_presets_are_validated_and_synced_without_device_selection(client):
    auth = register(client, "equalizer@example.com")
    preset_id = str(uuid.uuid4())
    payload = {
        "id": preset_id,
        "name": "  My Metal  ",
        "gains": [5.5, 2.5, -0.5, 0, 2, 3.5],
    }
    operation_id = str(uuid.uuid4())
    assert send(client, auth, "equalizer.preset.upsert", payload, operation_id).status_code == 200
    duplicate = send(client, auth, "equalizer.preset.upsert", payload, operation_id)
    assert duplicate.json() == {"version": 1, "duplicate": True}
    assert send(client, auth, "equalizer.preset.upsert", {
        **payload, "gains": [0, 1],
    }).status_code == 422
    assert send(client, auth, "equalizer.preset.upsert", {
        **payload, "gains": [0, 0, 0, 0, 0, 12.1],
    }).status_code == 422
    assert send(client, auth, "equalizer.preset.upsert", {
        **payload, "active": True,
    }).status_code == 200
    assert send(client, auth, "equalizer.preset.delete", {"id": preset_id}).status_code == 200

    operations = client.get("/sync/operations", headers=auth).json()["operations"]
    assert [operation["kind"] for operation in operations] == [
        "equalizer.preset.upsert",
        "equalizer.preset.upsert",
        "equalizer.preset.delete",
    ]
    assert operations[0]["payload"] == {
        "id": preset_id,
        "name": "My Metal",
        "gains": [5.5, 2.5, -0.5, 0.0, 2.0, 3.5],
    }
    assert "active" not in operations[1]["payload"]


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


def test_relay_transfers_one_track_between_two_clients(client):
    auth = register(client, "relay-two-clients@example.com")
    track_id = str(uuid.uuid4())
    assert send(client, auth, "track.upsert", {
        "id": track_id,
        "provider": "local",
        "source_id": "phone-a",
        "title": "one-track.mp3",
        "artist": None,
    }).status_code == 200

    token = auth["Authorization"].removeprefix("Bearer ")
    payload = b"audio bytes for exactly one track"
    with client.websocket_connect(
        f"/relay/{track_id}/source?token={token}&device=phone-a"
    ) as source:
        with client.websocket_connect(
            f"/relay/{track_id}/receive?token={token}"
        ) as receiver:
            assert source.receive_json() == {"type": "send", "track_id": track_id}
            source.send_bytes(payload)
            source.send_text("done")

            assert receiver.receive_bytes() == payload
            assert receiver.receive_text() == "done"


def test_resilient_playlist_and_device_status(client):
    auth = register(client, "resilient@example.com")
    existing_track = str(uuid.uuid4())
    missing_track = str(uuid.uuid4())
    assert send(client, auth, "track.upsert", {
        "id": existing_track, "provider": "youtube", "source_id": "yt1", "title": "Existing Song"
    }).status_code == 200

    playlist_id = str(uuid.uuid4())
    assert send(client, auth, "playlist.upsert", {"id": playlist_id, "name": "Mixed", "sort_key": 0}).status_code == 200

    # Setting tracks where one track is missing should succeed without 422
    assert send(client, auth, "playlist.set_tracks", {
        "playlist_id": playlist_id, "track_ids": [existing_track, missing_track]
    }).status_code == 200

    # Device status mutation
    assert send(client, auth, "track.device_status", {
        "track_id": existing_track, "device_id": "phone-abc", "status": "deleted", "device_name": "Android"
    }).status_code == 200


def test_playlist_set_tracks_preserves_exact_set_and_order(client):
    auth = register(client, "playlist-exact@example.com")
    tracks = [str(uuid.uuid4()) for _ in range(3)]
    for index, track_id in enumerate(tracks):
        assert send(client, auth, "track.upsert", {
            "id": track_id,
            "provider": "youtube",
            "source_id": f"exact-{index}",
            "title": f"Track {index}",
        }).status_code == 200

    playlist_id = str(uuid.uuid4())
    assert send(client, auth, "playlist.upsert", {
        "id": playlist_id,
        "name": "Exact set",
        "sort_key": 0,
    }).status_code == 200

    first_order = [tracks[0], tracks[1], tracks[2]]
    second_order = [tracks[2], tracks[0]]
    assert send(client, auth, "playlist.set_tracks", {
        "playlist_id": playlist_id,
        "track_ids": first_order,
    }).status_code == 200
    assert send(client, auth, "playlist.set_tracks", {
        "playlist_id": playlist_id,
        "track_ids": second_order,
    }).status_code == 200

    operations = client.get("/sync/operations", headers=auth).json()["operations"]
    playlist_changes = [
        operation["payload"]["track_ids"]
        for operation in operations
        if operation["kind"] == "playlist.set_tracks"
    ]
    assert playlist_changes[-2:] == [first_order, second_order]

    from maboy.models import PlaylistTrack
    session_generator = app.dependency_overrides[get_db]()
    try:
        db = next(session_generator)
        actual = [
            row.track_id
            for row in db.query(PlaylistTrack)
            .filter(PlaylistTrack.playlist_id == playlist_id)
            .order_by(PlaylistTrack.sort_key)
            .all()
        ]
    finally:
        session_generator.close()
    assert actual == second_order


def test_favorites_sync_and_smart_merge(client):
    from maboy.models import FavoriteTrack
    headers = register(client, "favs@example.com")

    # Create two tracks
    t1_id = str(uuid.uuid4())
    t2_id = str(uuid.uuid4())
    for t_id, title in [(t1_id, "Track 1"), (t2_id, "Track 2")]:
        client.post(
            "/sync/operations",
            headers=headers,
            json={
                "operation_id": str(uuid.uuid4()),
                "kind": "track.upsert",
                "payload": {
                    "id": t_id,
                    "title": title,
                    "artist": "Artist",
                    "provider": "local",
                    "source_id": f"src_{t_id}",
                },
            },
        )

    # 1. Device A likes Track 1
    r1 = client.post(
        "/sync/operations",
        headers=headers,
        json={
            "operation_id": str(uuid.uuid4()),
            "kind": "favorites.set",
            "payload": {"track_ids": [t1_id]},
        },
    )
    assert r1.status_code == 200

    # Verify pull contains [t1_id]
    pulled = client.get("/sync/operations", headers=headers).json()
    fav_ops = [op for op in pulled["operations"] if op["kind"] == "favorites.set"]
    assert fav_ops[-1]["payload"]["track_ids"] == [t1_id]

    # 2. Device B was offline and only had Track 2, sending favorites.set: [t2_id]
    r2 = client.post(
        "/sync/operations",
        headers=headers,
        json={
            "operation_id": str(uuid.uuid4()),
            "kind": "favorites.set",
            "payload": {"track_ids": [t2_id]},
        },
    )
    assert r2.status_code == 200

    # Server should smart merge: [t1_id, t2_id]
    pulled = client.get("/sync/operations", headers=headers).json()
    fav_ops = [op for op in pulled["operations"] if op["kind"] == "favorites.set"]
    assert fav_ops[-1]["payload"]["track_ids"] == [t1_id, t2_id]

    # Verify FavoriteTrack table in DB
    session_generator = app.dependency_overrides[get_db]()
    try:
        db = next(session_generator)
        db_tracks = [
            row.track_id
            for row in db.query(FavoriteTrack)
            .order_by(FavoriteTrack.sort_key)
            .all()
        ]
    finally:
        session_generator.close()
    assert db_tracks == [t1_id, t2_id]

    # 3. Intentional un-favorite: Device removes t1_id (sends [t2_id])
    r3 = client.post(
        "/sync/operations",
        headers=headers,
        json={
            "operation_id": str(uuid.uuid4()),
            "kind": "favorites.set",
            "payload": {"track_ids": [t2_id]},
        },
    )
    assert r3.status_code == 200
    pulled = client.get("/sync/operations", headers=headers).json()
    fav_ops = [op for op in pulled["operations"] if op["kind"] == "favorites.set"]
    assert fav_ops[-1]["payload"]["track_ids"] == [t2_id]

    # 4. Stale snapshot protection: client sends empty list while multiple items exist
    # First add t1_id back
    client.post(
        "/sync/operations",
        headers=headers,
        json={
            "operation_id": str(uuid.uuid4()),
            "kind": "favorites.set",
            "payload": {"track_ids": [t2_id, t1_id]},
        },
    )
    # Stale client sends [] (missing 2 tracks with no additions)
    r4 = client.post(
        "/sync/operations",
        headers=headers,
        json={
            "operation_id": str(uuid.uuid4()),
            "kind": "favorites.set",
            "payload": {"track_ids": []},
        },
    )
    assert r4.status_code == 200
    pulled = client.get("/sync/operations", headers=headers).json()
    fav_ops = [op for op in pulled["operations"] if op["kind"] == "favorites.set"]
    # Existing tracks are protected from bulk wipeout
    assert set(fav_ops[-1]["payload"]["track_ids"]) == {t1_id, t2_id}
