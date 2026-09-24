import asyncio
import base64
import logging
import os
import re
import shutil
import uuid
from pathlib import Path

from .captcha_solver import solve_recaptcha


logger = logging.getLogger(__name__)

_VIDEO_ID = re.compile(r"^[A-Za-z0-9_-]{11}$")
_MAX_PARALLEL_DOWNLOADS = 3
_download_slots = asyncio.Semaphore(_MAX_PARALLEL_DOWNLOADS)
_video_locks: dict[str, asyncio.Lock] = {}
_cookie_update_lock = asyncio.Lock()


class YouTubeDownloadError(RuntimeError):
    """Safe error returned to clients without leaking process arguments."""


def _cache_directory() -> Path:
    return Path(os.getenv("YOUTUBE_CACHE_DIR", "/var/lib/maboy/youtube")).resolve()


def _cookie_file() -> Path:
    return Path(
        os.getenv("YOUTUBE_COOKIES_FILE", "/run/secrets/youtube_cookies.txt")
    ).resolve()


def _max_cache_bytes() -> int:
    return int(os.getenv("YOUTUBE_CACHE_MAX_BYTES", str(20 * 1024**3)))


def _classify_failure(stderr: str) -> str:
    message = stderr.lower()
    if "cookies are no longer valid" in message or "likely been rotated" in message:
        return "Серверные cookies YouTube устарели"
    if "confirm your age" in message or "age-restricted" in message or "inappropriate for some users" in message:
        return "Видео 18+: серверу нужны актуальные cookies YouTube"
    if "video unavailable" in message or "this video is unavailable" in message:
        return "Видео недоступно на YouTube"
    if "captcha" in message or "not a bot" in message:
        return "YouTube запросил проверку, повторите загрузку"
    return "Сервер не смог скачать аудио с YouTube"


async def _prepare_cookie_copy(cache_dir: Path, temporary_base: Path) -> Path | None:
    """Create a writable per-process jar while keeping the host secret read-only."""
    source = _cookie_file()
    runtime = cache_dir / ".youtube_cookies.txt"
    async with _cookie_update_lock:
        if source.is_file() and (
            not runtime.is_file()
            or source.stat().st_mtime_ns > runtime.stat().st_mtime_ns
        ):
            shutil.copy2(source, runtime)
            runtime.chmod(0o600)
        if not runtime.is_file():
            return None
        task_cookie = Path(f"{temporary_base}.cookies.txt")
        shutil.copy2(runtime, task_cookie)
        task_cookie.chmod(0o600)
        return task_cookie


async def _promote_cookie_copy(task_cookie: Path | None, cache_dir: Path) -> None:
    if task_cookie is None or not task_cookie.is_file():
        return
    async with _cookie_update_lock:
        runtime = cache_dir / ".youtube_cookies.txt"
        task_cookie.replace(runtime)
        runtime.chmod(0o600)


def _prune_cache(cache_dir: Path, *, protected: Path | None = None) -> None:
    limit = _max_cache_bytes()
    files = [
        path
        for path in cache_dir.glob("*.mp3")
        if path.is_file() and path != protected
    ]
    total = sum(path.stat().st_size for path in files)
    for path in sorted(files, key=lambda item: item.stat().st_mtime):
        if total <= limit:
            break
        try:
            size = path.stat().st_size
            path.unlink()
            total -= size
        except OSError:
            logger.warning("Unable to prune YouTube cache file %s", path.name)


_AGE_PLAYER_CLIENTS = (
    "tv_embedded",
    "web_embedded",
    "tv",
    "web_safari",
)


def _is_age_restriction(diagnostics: str) -> bool:
    lowered = diagnostics.lower()
    return (
        "confirm your age" in lowered
        or "age-restricted" in lowered
        or "inappropriate for some users" in lowered
        or "sign in to confirm your age" in lowered
    )


def _without_player_client(args: list[str]) -> list[str]:
    cleaned: list[str] = []
    skip_value = False
    for arg in args:
        if skip_value:
            skip_value = False
            continue
        if arg == "--extractor-args":
            skip_value = True
            continue
        cleaned.append(arg)
    return cleaned


async def _run_yt_dlp(
    args: list[str], cache_dir: Path, temporary_base: Path
) -> tuple[int, str, Path]:
    process = await asyncio.create_subprocess_exec(
        *args,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    try:
        _, stderr_bytes = await asyncio.wait_for(process.communicate(), timeout=240)
    except asyncio.TimeoutError as exc:
        process.kill()
        await process.wait()
        for leftover in cache_dir.glob(f"{temporary_base.name}.*"):
            leftover.unlink(missing_ok=True)
        raise YouTubeDownloadError(
            "Сервер превысил таймаут скачивания YouTube"
        ) from exc
    produced = Path(f"{temporary_base}.mp3")
    return (
        process.returncode or 0,
        stderr_bytes.decode("utf-8", errors="replace"),
        produced,
    )


async def ensure_youtube_audio(video_id: str) -> Path:
    """Return a cached MP3, downloading it once for every Maboy account."""
    if not _VIDEO_ID.fullmatch(video_id):
        raise YouTubeDownloadError("Некорректный идентификатор YouTube")

    cache_dir = _cache_directory()
    cache_dir.mkdir(parents=True, exist_ok=True)
    target = cache_dir / f"{video_id}.mp3"
    if target.is_file() and target.stat().st_size > 5_000:
        target.touch()
        return target

    lock = _video_locks.setdefault(video_id, asyncio.Lock())
    async with lock:
        if target.is_file() and target.stat().st_size > 5_000:
            target.touch()
            return target

        async with _download_slots:
            _prune_cache(cache_dir, protected=target)
            temporary_base = cache_dir / f".{video_id}-{uuid.uuid4().hex}"
            output_template = f"{temporary_base}.%(ext)s"
            task_cookie = await _prepare_cookie_copy(cache_dir, temporary_base)
            args = [
                "yt-dlp",
                "--js-runtimes",
                "node:/usr/local/bin/node",
                "--remote-components",
                "ejs:github",
            ]
            if task_cookie is not None:
                args.extend(("--cookies", str(task_cookie)))
            args.extend(
                (
                    "--no-playlist",
                    "-x",
                    "--audio-format",
                    "mp3",
                    "--audio-quality",
                    "0",
                    "-o",
                    output_template,
                    f"https://www.youtube.com/watch?v={video_id}",
                )
            )

            returncode, stderr, produced = await _run_yt_dlp(
                args, cache_dir, temporary_base
            )
            if returncode != 0 or not produced.is_file():
                logger.warning(
                    "yt-dlp failed for %s: %s", video_id, stderr[-2_000:]
                )
                lowered = stderr.lower()
                if "captcha" in lowered or "not a bot" in lowered:
                    token = await asyncio.to_thread(
                        solve_recaptcha, "https://www.youtube.com/watch", video_id, 30
                    )
                    if token:
                        po_token = base64.b64encode(token.encode()).decode()
                        returncode, stderr, produced = await _run_yt_dlp(
                            [
                                *args,
                                "--extractor-args",
                                f"youtube:po_token=web.gvs+{po_token}",
                            ],
                            cache_dir,
                            temporary_base,
                        )
                if (
                    (returncode != 0 or not produced.is_file())
                    and task_cookie is not None
                    and task_cookie.is_file()
                    and _is_age_restriction(stderr)
                ):
                    # Default web player still age-gates a logged-in cookie jar.
                    # Embedded and TV players accept the same jar.
                    base_args = _without_player_client(args)
                    for player_client in _AGE_PLAYER_CLIENTS:
                        for leftover in cache_dir.glob(f"{temporary_base.name}.*"):
                            leftover.unlink(missing_ok=True)
                        logger.info(
                            "Retrying age-restricted %s via player client %s",
                            video_id,
                            player_client,
                        )
                        returncode, stderr, produced = await _run_yt_dlp(
                            [
                                *base_args,
                                "--extractor-args",
                                f"youtube:player_client={player_client}",
                            ],
                            cache_dir,
                            temporary_base,
                        )
                        if returncode == 0 and produced.is_file():
                            break
                if returncode != 0 or not produced.is_file():
                    for leftover in cache_dir.glob(f"{temporary_base.name}.*"):
                        leftover.unlink(missing_ok=True)
                    raise YouTubeDownloadError(_classify_failure(stderr))

            produced.replace(target)
            await _promote_cookie_copy(task_cookie, cache_dir)
            _prune_cache(cache_dir, protected=target)
            return target
