"""Сквозное ядро API: один пользователь, одна база, весь путь синхронизации.

Запуск вместе с регрессией: pytest server/tests
Только ядро: pytest server/tests/test_core.py
"""

import uuid

import pytest
from starlette.testclient import TestClient

from maboy.app import app, get_db
from maboy.models import FavoriteTrack, PlaylistTrack, Track


@pytest.fixture(scope="module")
def core():
    """Одна сессия на весь сквозной сценарий, а не новая БД на каждый шаг."""
    from sqlalchemy import create_engine
    from sqlalchemy.orm import sessionmaker
    from sqlalchemy.pool import StaticPool

    from maboy.db import Base

    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    sessions = sessionmaker(bind=engine, autoflush=False, autocommit=False)

    def override_db():
        db = sessions()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = override_db
    with TestClient(app) as client:
        yield {"client": client, "version": 0}
    app.dependency_overrides.clear()
    engine.dispose()


def _send(core, kind, payload):
    response = core["client"].post(
        "/sync/operations",
        headers=core["auth"],
        json={
            "operation_id": str(uuid.uuid4()),
            "kind": kind,
            "payload": payload,
        },
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["version"] == core["version"] + 1
    assert body["duplicate"] is False
    core["version"] = body["version"]
    return body


def _rows(model, order_by):
    session = app.dependency_overrides[get_db]()
    try:
        db = next(session)
        return list(db.query(model).order_by(order_by).all())
    finally:
        session.close()


def test_01_register_and_login(core):
    client = core["client"]
    email = f"core-{uuid.uuid4()}@example.com"
    registered = client.post(
        "/auth/register", json={"email": email, "password": "correct-password"}
    )
    assert registered.status_code == 201
    assert registered.json()["access_token"]
    assert client.post(
        "/auth/login", json={"email": email, "password": "wrong-password"}
    ).status_code == 401
    logged_in = client.post(
        "/auth/login", json={"email": email, "password": "correct-password"}
    )
    assert logged_in.status_code == 200
    core["auth"] = {"Authorization": f"Bearer {logged_in.json()['access_token']}"}


def test_02_track_playlist_and_queue_sync(core):
    track_id = str(uuid.uuid4())
    playlist_id = str(uuid.uuid4())
    core["track_id"] = track_id
    core["playlist_id"] = playlist_id

    _send(core, "track.upsert", {
        "id": track_id,
        "provider": "local",
        "source_id": "phone-library",
        "title": "Core Song",
        "artist": "Core Artist",
    })
    _send(core, "track.set_order", {"track_ids": [track_id]})
    _send(core, "playlist.upsert", {"id": playlist_id, "name": "Core", "sort_key": 0})
    _send(core, "playlist.set_tracks", {
        "playlist_id": playlist_id, "track_ids": [track_id],
    })
    queue_item = str(uuid.uuid4())
    _send(core, "queue.set", {
        "items": [{"id": queue_item, "track_id": track_id}],
        "index": 0,
        "position_ms": 1500,
    })

    operations = core["client"].get(
        "/sync/operations", headers=core["auth"]
    ).json()["operations"]
    assert [item["kind"] for item in operations] == [
        "track.upsert",
        "track.set_order",
        "playlist.upsert",
        "playlist.set_tracks",
        "queue.set",
    ]
    assert operations[-1]["payload"]["position_ms"] == 1500
    assert [row.track_id for row in _rows(PlaylistTrack, PlaylistTrack.sort_key)] == [track_id]


def test_03_favorites_merge_and_intentional_removal(core):
    kept = core["track_id"]
    added = str(uuid.uuid4())
    core["added_id"] = added
    _send(core, "track.upsert", {
        "id": added,
        "provider": "local",
        "source_id": "phone",
        "title": "Second.mp3",
        "artist": None,
    })
    _send(core, "favorites.set", {"track_ids": [kept]})
    # Офлайн-устройство знает только второй трек: сервер сливает, а не затирает.
    _send(core, "favorites.set", {"track_ids": [added]})
    pulled = core["client"].get("/sync/operations", headers=core["auth"]).json()["operations"]
    favorites = [item for item in pulled if item["kind"] == "favorites.set"]
    assert favorites[-1]["payload"]["track_ids"] == [kept, added]

    _send(core, "favorites.set", {"track_ids": [added]})
    pulled = core["client"].get("/sync/operations", headers=core["auth"]).json()["operations"]
    favorites = [item for item in pulled if item["kind"] == "favorites.set"]
    assert favorites[-1]["payload"]["track_ids"] == [added]
    assert [row.track_id for row in _rows(FavoriteTrack, FavoriteTrack.sort_key)] == [added]


def test_04_equalizer_is_canonical_and_rejects_bad_gains(core):
    client = core["client"]
    preset_id = str(uuid.uuid4())
    payload = {
        "id": preset_id,
        "name": "  Core Metal  ",
        "gains": [5.5, 2.5, -0.5, 0, 2, 3.5],
    }
    _send(core, "equalizer.preset.upsert", payload)
    assert client.post(
        "/sync/operations",
        headers=core["auth"],
        json={
            "operation_id": str(uuid.uuid4()),
            "kind": "equalizer.preset.upsert",
            "payload": {**payload, "gains": [0, 1]},
        },
    ).status_code == 422
    pulled = client.get("/sync/operations", headers=core["auth"]).json()["operations"]
    stored = [item for item in pulled if item["kind"] == "equalizer.preset.upsert"][-1]
    assert stored["payload"]["name"] == "Core Metal"
    assert stored["payload"]["gains"] == [5.5, 2.5, -0.5, 0.0, 2.0, 3.5]
    assert "active" not in stored["payload"]


def test_05_accounts_are_isolated_and_relay_stays_with_owner(core):
    client = core["client"]
    stranger = client.post(
        "/auth/register",
        json={
            "email": f"stranger-{uuid.uuid4()}@example.com",
            "password": "correct-password",
        },
    )
    assert stranger.status_code == 201
    stranger_auth = {"Authorization": f"Bearer {stranger.json()['access_token']}"}
    snapshot = client.get("/sync/operations", headers=stranger_auth)
    assert snapshot.status_code == 200
    assert snapshot.json()["operations"] == []

    token = stranger_auth["Authorization"].removeprefix("Bearer ")
    with pytest.raises(Exception):
        with client.websocket_connect(f"/relay/{core['track_id']}/receive?token={token}"):
            pass
    stored = {row.id for row in _rows(Track, Track.title)}
    assert {core["track_id"], core["added_id"]} <= stored


def test_06_owner_relays_one_track_and_reports_offline_peer(core):
    client = core["client"]
    token = core["auth"]["Authorization"].removeprefix("Bearer ")
    track_id = core["added_id"]
    payload = b"one-track-bytes"

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

    with client.websocket_connect(
        f"/relay/{track_id}/receive?token={token}&device=phone-a"
    ) as receiver:
        assert receiver.receive_text() == "peer_offline"


def test_07_friend_receives_track_in_own_library(core):
    client = core["client"]
    owner = core["auth"]
    friend = client.post("/auth/register", json={
        "email": f"friend-{uuid.uuid4()}@example.com", "password": "correct-password",
    })
    assert friend.status_code == 201
    friend_auth = {"Authorization": f"Bearer {friend.json()['access_token']}"}

    assert client.put("/account/nickname", headers=owner, json={"nickname": "owner_one"}).status_code == 200
    assert client.put("/account/nickname", headers=friend_auth, json={"nickname": "friend_two"}).status_code == 200
    requested = client.post("/friends/requests", headers=owner, json={"nickname": "friend_two"})
    assert requested.status_code == 201
    request_id = client.get("/friends", headers=friend_auth).json()["incoming"][0]["id"]
    assert client.post(f"/friends/requests/{request_id}/accept", headers=friend_auth).status_code == 200

    shared = client.post("/friends/friend_two/shares", headers=owner, json={"track_id": core["track_id"]})
    assert shared.status_code == 201
    share_id = client.get("/friends", headers=friend_auth).json()["shares"][0]["id"]
    accepted = client.post(f"/friends/shares/{share_id}/accept", headers=friend_auth)
    assert accepted.status_code == 200, accepted.text
    operations = client.get("/sync/operations", headers=friend_auth).json()["operations"]
    assert operations[-1]["kind"] == "track.upsert"
    assert operations[-1]["payload"]["title"] == "Core Song"
    assert operations[-1]["payload"]["id"] == accepted.json()["track_id"]
    payload = b"ID3real-track-bytes"
    owner_token = owner["Authorization"].removeprefix("Bearer ")
    friend_token = friend_auth["Authorization"].removeprefix("Bearer ")
    source_id = core["track_id"]
    with client.websocket_connect(f"/relay/{source_id}/source?token={owner_token}&device=owner-phone") as source:
        with client.websocket_connect(f"/relay/{source_id}/receive?token={friend_token}") as receiver:
            assert source.receive_json() == {"type": "send", "track_id": source_id}
            source.send_bytes(payload)
            source.send_text("done")
            assert receiver.receive_bytes() == payload
            assert receiver.receive_text() == "done"



