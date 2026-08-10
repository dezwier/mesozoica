"""Bounded, observable HTTP access shared by external knowledge sources."""

from __future__ import annotations

import logging
import gzip
import random
import time
from collections.abc import Callable
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from typing import Any

import httpx

from mesozoica_ai.common.errors import RateLimitedError, SourceFetchError

logger = logging.getLogger(__name__)
RETRYABLE_STATUS_CODES = frozenset({500, 502, 503, 504})


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
        response = self._get_response(url, params=params, headers=headers, source=source)
        try:
            payload = response.json()
        except ValueError as exc:
            raise SourceFetchError(f"{source} returned invalid JSON") from exc
        if not isinstance(payload, dict):
            raise SourceFetchError(f"{source} returned JSON that is not an object")
        return payload

    def get_text(
        self, url: str, *, params: dict[str, Any], headers: dict[str, str], source: str = "unknown"
    ) -> str:
        """Return response text without logging query parameters or body content."""
        response = self._get_response(url, params=params, headers=headers, source=source)
        text = _decode_response_text(response)
        if not text.strip():
            raise SourceFetchError(f"{source} returned empty content")
        return text

    def _get_response(
        self,
        url: str,
        *,
        params: dict[str, Any],
        headers: dict[str, str],
        source: str,
    ) -> httpx.Response:
        for attempt in range(1, self.attempts + 1):
            try:
                response = self.client.get(url, params=params, headers=headers)
            except httpx.TransportError as exc:
                logger.warning(
                    "%s transport error on attempt %s/%s (%s); retrying",
                    source,
                    attempt,
                    self.attempts,
                    exc.__class__.__name__,
                )
                if attempt == self.attempts:
                    raise SourceFetchError(
                        f"{source} transport failed after {attempt} attempts"
                    ) from exc
                self.sleeper(self._backoff(attempt, None))
                continue
            status = response.status_code
            if status == 429:
                retry_after = response.headers.get("Retry-After")
                logger.warning(
                    "%s HTTP 429 Too Many Requests%s — stopping",
                    source,
                    f" (Retry-After: {retry_after})" if retry_after else "",
                )
                raise RateLimitedError(source, retry_after=retry_after)
            if status in RETRYABLE_STATUS_CODES and attempt < self.attempts:
                logger.warning(
                    "%s HTTP %s on attempt %s/%s; retrying",
                    source,
                    status,
                    attempt,
                    self.attempts,
                )
                self.sleeper(self._backoff(attempt, response.headers.get("Retry-After")))
                continue
            try:
                response.raise_for_status()
            except httpx.HTTPStatusError as exc:
                raise SourceFetchError(f"{source} returned HTTP {status}") from exc
            if attempt > 1:
                logger.info("%s fetch succeeded on attempt %s", source, attempt)
            return response
        raise SourceFetchError(f"{source} request exhausted retries")

    def _backoff(self, attempt: int, retry_after: str | None) -> float:
        retry_delay = _retry_after_seconds(retry_after)
        if retry_delay is not None:
            return min(self.max_backoff_seconds, max(0, retry_delay))
        return min(self.max_backoff_seconds, 0.5 * 2 ** (attempt - 1)) + self.jitter() * 0.25


def _decode_response_text(response: httpx.Response) -> str:
    """Decode body text, including raw gzip payloads without Content-Encoding."""
    content = response.content
    content_type = (response.headers.get("content-type") or "").casefold()
    if content[:2] == b"\x1f\x8b" or "gzip" in content_type:
        try:
            content = gzip.decompress(content)
        except OSError as exc:
            raise SourceFetchError("response claimed gzip but could not be decompressed") from exc
    return content.decode(response.encoding or "utf-8", errors="replace")


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
