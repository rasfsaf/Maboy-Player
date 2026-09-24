import asyncio
import os
import shutil
import sys
from pathlib import Path

import pytest

from maboy import youtube_media
from maboy.youtube_media import ensure_youtube_audio

AGE_RESTRICTED_VIDEO = "8vKm3w7cRJQ"
pytestmark = pytest.mark.skipif(
    os.getenv("MABOY_LIVE_YOUTUBE") != "1",
    reason="set MABOY_LIVE_YOUTUBE=1 to download a real age-restricted video",
)


def test_live_age_restricted_video_downloads(monkeypatch, tmp_path):
    node = shutil.which("node")
    assert node, "Node.js is required for the YouTube player challenge"
    real_spawn = asyncio.create_subprocess_exec

    async def spawn(*args, **kwargs):
        command = list(args)
        if command and Path(command[0]).name.startswith("yt-dlp"):
            rewritten = [sys.executable, "-m", "yt_dlp"]
            skip_runtime = False
            for arg in command[1:]:
                if skip_runtime:
                    skip_runtime = False
                    if arg.startswith("node:"):
                        rewritten.extend(["--js-runtimes", f"node:{Path(node).as_posix()}"])
                    else:
                        rewritten.append(arg)
                    continue
                if arg == "--js-runtimes":
                    skip_runtime = True
                    continue
                rewritten.append(arg)
            command = rewritten
        return await real_spawn(*command, **kwargs)

    monkeypatch.setattr(youtube_media.asyncio, "create_subprocess_exec", spawn)
    monkeypatch.setenv("YOUTUBE_CACHE_DIR", str(tmp_path / "cache"))
    monkeypatch.setenv(
        "YOUTUBE_COOKIES_FILE",
        str(Path(__file__).parents[1] / "secrets" / "youtube_cookies.txt"),
    )

    audio = asyncio.run(ensure_youtube_audio(AGE_RESTRICTED_VIDEO))

    assert audio.is_file()
    assert audio.stat().st_size > 100_000
    assert audio.suffix == ".mp3"
    header = audio.read_bytes()[:3]
    assert header == b"ID3" or header[0] == 0xFF
