import json
import os
import time
import urllib.request
from typing import Any

RUCAPTCHA_CREATE = "https://api.rucaptcha.com/createTask"
RUCAPTCHA_RESULT = "https://api.rucaptcha.com/getTaskResult"
CAPMONSTER_CREATE = "https://api.capmonster.cloud/createTask"
CAPMONSTER_RESULT = "https://api.capmonster.cloud/getTaskResult"


class CaptchaSolverError(RuntimeError):
    pass


def _post(url: str, payload: dict[str, Any], timeout: float) -> dict[str, Any]:
    data = json.dumps(payload).encode()
    request = urllib.request.Request(
        url, data=data, headers={"content-type": "application/json"}
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        body = json.loads(response.read().decode())
    if not isinstance(body, dict):
        raise CaptchaSolverError("bad response")
    return body


def _poll(url: str, api_key: str, task_id: Any, deadline: float) -> str:
    while time.monotonic() < deadline:
        time.sleep(2)
        body = _post(url, {"clientKey": api_key, "taskId": task_id}, timeout=30)
        if body.get("errorId"):
            raise CaptchaSolverError("poll failed")
        if body.get("status") == "ready":
            solution = body.get("solution") or {}
            token = solution.get("gRecaptchaResponse") if isinstance(solution, dict) else None
            if isinstance(token, str) and token:
                return token
            raise CaptchaSolverError("empty solution")
    raise CaptchaSolverError("timeout")


def _solve_provider(create_url: str, result_url: str, api_key: str, task: dict[str, Any], timeout: float) -> str:
    created = _post(create_url, {"clientKey": api_key, "task": task}, timeout=30)
    if created.get("errorId") or created.get("taskId") is None:
        raise CaptchaSolverError("create failed")
    return _poll(result_url, api_key, created["taskId"], time.monotonic() + timeout)


def solve_recaptcha(website_url: str, website_key: str, timeout: float = 180) -> str | None:
    task = {"type": "RecaptchaV2TaskProxyless", "websiteURL": website_url, "websiteKey": website_key}
    providers = [
        (os.environ.get("RUCAPTCHA_KEY", "").strip(), RUCAPTCHA_CREATE, RUCAPTCHA_RESULT),
        (os.environ.get("CAPMONSTER_KEY", "").strip(), CAPMONSTER_CREATE, CAPMONSTER_RESULT),
    ]
    last: Exception | None = None
    for key, create_url, result_url in providers:
        if not key:
            continue
        try:
            return _solve_provider(create_url, result_url, key, task, timeout)
        except (CaptchaSolverError, OSError, ValueError) as error:
            last = error
    if last is not None:
        return None
    return None
