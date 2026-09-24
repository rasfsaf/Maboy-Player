"""Android YouTube path: submit a link, stream the audio, receive the file, install it.

Android never runs yt-dlp itself. The client registers the link as a track and then
reads GET /youtube/tracks/{id}/audio, which the server streams in chunks. This test
walks that path with a local payload instead of the live YouTube network.
"""

import asyncio
import uuid
from urllib.parse import parse_qs, urlparse

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


async def stream_body(application, track_id, authorization):
    chunks = []

    async def receive():
        return {"type": "http.request", "body": b"", "more_body": False}

    async def send_message(message):
        if message["type"] == "http.response.body" and message.get("body"):
            chunks.append(message["body"])

    scope = {
        "type": "http",
        "asgi": {"version": "3.0"},
        "http_version": "1.1",
        "method": "GET",
        "scheme": "http",
        "path": f"/youtube/tracks/{track_id}/audio",
        "raw_path": f"/youtube/tracks/{track_id}/audio".encode(),
        "query_string": b"",
        "headers": [(b"authorization", authorization.encode())],
        "client": ("127.0.0.1", 123),
        "server": ("testserver", 80),
    }
    await application(scope, receive, send_message)
    return chunks


def register(client, email):
    response = client.post("/auth/register", json={"email": email, "password": "long-password-123"})
    assert response.status_code == 201, response.text
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def send(client, headers, kind, payload):
    return client.post(
        "/sync/operations",
        headers=headers,
        json={"operation_id": str(uuid.uuid4()), "kind": kind, "payload": payload},
    )


def test_android_link_streams_then_installs(client, monkeypatch, tmp_path):
    payload = bytes(range(256)) * 400  # larger than one 64 KiB stream chunk
    cached = tmp_path / "android-source.mp3"
    cached.write_bytes(payload)

    async def fake_ensure(video_id, *, cookies_path=None):
        assert video_id == "dQw4w9WgXcQ"
        return cached

    monkeypatch.setattr("maboy.app.ensure_youtube_audio", fake_ensure)

    link = "https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=ignored"
    video_id = parse_qs(urlparse(link).query)["v"][0]
    assert video_id == "dQw4w9WgXcQ"

    android = register(client, "android@example.com")
    track_id = str(uuid.uuid4())
    submitted = send(
        client,
        android,
        "track.upsert",
        {"id": track_id, "provider": "youtube", "source_id": video_id, "title": "Android song"},
    )
    assert submitted.status_code == 200, submitted.text

    with client.stream("GET", f"/youtube/tracks/{track_id}/audio", headers=android) as response:
        assert response.status_code == 200, response.read()
        assert response.headers["content-type"].startswith("audio/mpeg")
        assert "attachment" in response.headers["content-disposition"]
        received = b"".join(response.iter_bytes())

    body_chunks = asyncio.run(stream_body(app, track_id, android["Authorization"]))
    assert len(body_chunks) > 1
    assert b"".join(body_chunks) == payload
    assert received == payload

    installed = tmp_path / "installed" / f"{track_id}.mp3"
    installed.parent.mkdir()
    temporary = installed.with_suffix(".part")
    temporary.write_bytes(received)
    temporary.replace(installed)

    assert installed.is_file()
    assert installed.read_bytes() == payload
    assert installed.stat().st_size == len(payload)


def test_android_stream_rejects_a_foreign_account(client, monkeypatch, tmp_path):
    cached = tmp_path / "owned.mp3"
    cached.write_bytes(b"owned-audio")
    async def fake_ensure(video_id, **_):
        return cached

    monkeypatch.setattr("maboy.app.ensure_youtube_audio", fake_ensure)

    owner = register(client, "owner@example.com")
    stranger = register(client, "stranger@example.com")
    track_id = str(uuid.uuid4())
    assert send(
        client,
        owner,
        "track.upsert",
        {"id": track_id, "provider": "youtube", "source_id": "dQw4w9WgXcQ", "title": "Private"},
    ).status_code == 200

    denied = client.get(f"/youtube/tracks/{track_id}/audio", headers=stranger)
    assert denied.status_code == 404
    assert not (tmp_path / "installed").exists()
    assert cached.read_bytes() == b"owned-audio"
