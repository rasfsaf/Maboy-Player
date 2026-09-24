import asyncio
from pathlib import Path

import pytest

from maboy.youtube_media import (
    _AGE_PLAYER_CLIENTS,
    _is_age_restriction,
    _without_player_client,
    ensure_youtube_audio,
)


def test_age_restriction_detects_youtube_age_gate():
    assert _is_age_restriction("Sign in to confirm your age")
    assert _is_age_restriction("This video is age-restricted")
    assert not _is_age_restriction("Video unavailable")


def test_player_client_args_are_replaced_for_age_retry():
    args = [
        "yt-dlp",
        "--cookies",
        "cookies.txt",
        "--extractor-args",
        "youtube:player_client=web",
        "https://www.youtube.com/watch?v=abc",
    ]

    cleaned = _without_player_client(args)

    assert "--extractor-args" not in cleaned
    assert cleaned[-1].endswith("v=abc")


def test_age_gate_retries_cookie_capable_player_clients(monkeypatch, tmp_path):
    calls: list[list[str]] = []
    age_error = "ERROR: Sign in to confirm your age. This video may be inappropriate"

    async def fake_run(args, cache_dir, temporary_base):
        calls.append(args)
        if len(calls) <= 2:
            return 1, age_error, Path(f"{temporary_base}.mp3")
        produced = Path(f"{temporary_base}.mp3")
        produced.write_bytes(b"mp3")
        return 0, "", produced

    monkeypatch.setattr("maboy.youtube_media._run_yt_dlp", fake_run)
    monkeypatch.setattr(
        "maboy.youtube_media._cache_directory", lambda: tmp_path / "cache"
    )
    monkeypatch.setattr(
        "maboy.youtube_media._cookie_file",
        lambda: tmp_path / "youtube_cookies.txt",
    )
    (tmp_path / "youtube_cookies.txt").write_text("# Netscape\n", encoding="utf-8")

    result = asyncio.run(ensure_youtube_audio("dQw4w9WgXcQ"))

    assert result.is_file()
    assert len(calls) == 3
    assert not any("player_client" in arg for arg in calls[0])
    assert f"youtube:player_client={_AGE_PLAYER_CLIENTS[0]}" in calls[1]
    assert f"youtube:player_client={_AGE_PLAYER_CLIENTS[1]}" in calls[2]


def test_age_gate_without_cookies_does_not_retry_clients(monkeypatch, tmp_path):
    calls: list[list[str]] = []

    async def fake_run(args, cache_dir, temporary_base):
        calls.append(args)
        return 1, "ERROR: Sign in to confirm your age", Path(f"{temporary_base}.mp3")

    monkeypatch.setattr("maboy.youtube_media._run_yt_dlp", fake_run)
    monkeypatch.setattr(
        "maboy.youtube_media._cache_directory", lambda: tmp_path / "cache"
    )
    monkeypatch.setattr(
        "maboy.youtube_media._cookie_file",
        lambda: tmp_path / "missing-cookies.txt",
    )

    with pytest.raises(Exception, match="18\\+"):
        asyncio.run(ensure_youtube_audio("dQw4w9WgXcQ"))

    assert len(calls) == 1
