"""Bounded, observable HTTP access shared by external knowledge sources."""

from __future__ import annotations

import logging
import random
import time
from collections.abc import Callable
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from typing import Any

import httpx

from mesozoica_ai.common.errors import SourceFetchError

logger = logging.getLogger(__name__)
RETRYABLE_STATUS_CODES = frozenset({429, 500, 502, 503, 504})


class RetryingJsonClient:
    """Fetch JSON while retrying only throttling, transient server, and transport errors."""

    def __init__(
        self,
        client: httpx.Client | None = None,
        *,
        attempts: int = 4,
        connect_timeout_seconds: float = 10,
        read_timeout_seconds: float = 30,
        max_backoff_seconds: float = 8,
        sleeper: Callable[[float], None] = time.sleep,
        jitter: Callable[[], float] = random.random,
    ) -> None:
        self._owns_client = client is None
        self.client = client or httpx.Client(
            timeout=httpx.Timeout(read_timeout_seconds, connect=connect_timeout_seconds)
        )
        self.attempts = attempts
        self.max_backoff_seconds = max_backoff_seconds
        self.sleeper = sleeper
        self.jitter = jitter

    def __enter__(self) -> "RetryingJsonClient":
        return self

    def __exit__(self, *_: object) -> None:
        self.close()

    def close(self) -> None:
        """Close only a client whose lifecycle this wrapper owns."""
        if self._owns_client:
            self.client.close()

    def get(
        self, url: str, *, params: dict[str, Any], headers: dict[str, str], source: str = "unknown"
    ) -> dict[str, Any]:
        """Return one JSON object without logging query parameters or response content."""
        for attempt in range(1, self.attempts + 1):
            try:
                response = self.client.get(url, params=params, headers=headers)
            except httpx.TransportError as exc:
                logger.warning("rag.source.retry", extra={"rag": {"source": source, "attempt": attempt, "status": "transport"}})
                if attempt == self.attempts:
                    raise SourceFetchError(f"{source} transport failed after {attempt} attempts") from exc
                self.sleeper(self._backoff(attempt, None))
                continue
            status = response.status_code
            if status in RETRYABLE_STATUS_CODES and attempt < self.attempts:
                logger.warning("rag.source.retry", extra={"rag": {"source": source, "attempt": attempt, "status": status}})
                self.sleeper(self._backoff(attempt, response.headers.get("Retry-After")))
                continue
            try:
                response.raise_for_status()
            except httpx.HTTPStatusError as exc:
                raise SourceFetchError(f"{source} returned HTTP {status}") from exc
            try:
                payload = response.json()
            except ValueError as exc:
                raise SourceFetchError(f"{source} returned invalid JSON") from exc
            if not isinstance(payload, dict):
                raise SourceFetchError(f"{source} returned JSON that is not an object")
            logger.info("rag.source.fetch", extra={"rag": {"source": source, "attempt": attempt, "status": status}})
            return payload
        raise SourceFetchError(f"{source} request exhausted retries")

    def _backoff(self, attempt: int, retry_after: str | None) -> float:
        retry_delay = _retry_after_seconds(retry_after)
        if retry_delay is not None:
            return min(self.max_backoff_seconds, max(0, retry_delay))
        return min(self.max_backoff_seconds, 0.5 * 2 ** (attempt - 1)) + self.jitter() * 0.25


def _retry_after_seconds(value: str | None, *, now: datetime | None = None) -> float | None:
    """Parse either Retry-After seconds or the RFC HTTP-date form."""
    if not value:
        return None
    try:
        return float(value)
    except ValueError:
        try:
            target = parsedate_to_datetime(value)
        except (TypeError, ValueError):
            return None
        if target.tzinfo is None:
            target = target.replace(tzinfo=timezone.utc)
        return (target - (now or datetime.now(timezone.utc))).total_seconds()
