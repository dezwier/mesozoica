from __future__ import annotations

import time
from collections.abc import Callable
from typing import Any

import httpx


class RetryingJsonClient:
    def __init__(
        self,
        client: httpx.Client | None = None,
        *,
        attempts: int = 4,
        sleeper: Callable[[float], None] = time.sleep,
    ) -> None:
        self.client = client or httpx.Client(timeout=30)
        self.attempts = attempts
        self.sleeper = sleeper

    def get(self, url: str, *, params: dict[str, Any], headers: dict[str, str]) -> dict:
        last_error: Exception | None = None
        for attempt in range(1, self.attempts + 1):
            try:
                response = self.client.get(url, params=params, headers=headers)
                if response.status_code == 429 or response.status_code >= 500:
                    retry_after = response.headers.get("Retry-After")
                    delay = float(retry_after) if retry_after else min(8.0, 0.5 * 2 ** (attempt - 1))
                    if attempt < self.attempts:
                        self.sleeper(delay)
                        continue
                response.raise_for_status()
                payload = response.json()
                if not isinstance(payload, dict):
                    raise ValueError("Expected a JSON object from source API")
                return payload
            except (httpx.HTTPError, ValueError) as exc:
                last_error = exc
                if attempt < self.attempts:
                    self.sleeper(min(8.0, 0.5 * 2 ** (attempt - 1)))
                    continue
                raise
        raise RuntimeError("Source request failed") from last_error
