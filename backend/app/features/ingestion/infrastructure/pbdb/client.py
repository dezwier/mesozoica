"""HTTP client for the Paleobiology Database (PBDB) API v1.2."""

from __future__ import annotations

import time
from typing import Any
from urllib.parse import urlencode

import httpx
from tenacity import retry, retry_if_exception_type, stop_after_attempt, wait_exponential

_RETRYABLE = (httpx.HTTPStatusError, httpx.TransportError)

PBDB_BASE_URL = "https://paleobiodb.org/data1.2"
PBDB_USER_AGENT = "MesozoicaBot/1.0 (dev; contact@mesozoica.app)"
PBDB_REQUEST_DELAY_MS = 300
PBDB_PAGE_LIMIT = 500
PBDB_SHOW_BLOCKS = "full"


class PbdbClient:
    """Polite PBDB API client with rate limiting and retries."""

    def __init__(
        self,
        *,
        base_url: str = PBDB_BASE_URL,
        user_agent: str = PBDB_USER_AGENT,
        delay_ms: int = PBDB_REQUEST_DELAY_MS,
        page_limit: int = PBDB_PAGE_LIMIT,
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self.user_agent = user_agent
        self.delay_s = delay_ms / 1000.0
        self.page_limit = page_limit
        self._last_request_at = 0.0
        self._http = httpx.Client(
            headers={"User-Agent": self.user_agent},
            timeout=httpx.Timeout(30.0, connect=10.0),
            follow_redirects=True,
        )

    def close(self) -> None:
        self._http.close()

    def __enter__(self) -> PbdbClient:
        return self

    def __exit__(self, *args: object) -> None:
        self.close()

    def _throttle(self) -> None:
        elapsed = time.monotonic() - self._last_request_at
        if elapsed < self.delay_s:
            time.sleep(self.delay_s - elapsed)

    @retry(
        retry=retry_if_exception_type(_RETRYABLE),
        stop=stop_after_attempt(4),
        wait=wait_exponential(multiplier=1, min=1, max=30),
        reraise=True,
    )
    def _request(self, method: str, url: str, **kwargs: Any) -> httpx.Response:
        self._throttle()
        response = self._http.request(method, url, **kwargs)
        self._last_request_at = time.monotonic()
        if response.status_code in (429, 500, 502, 503, 504):
            response.raise_for_status()
        response.raise_for_status()
        return response

    def list_occurrences(self, *, base_name: str, offset: int = 0) -> dict[str, Any]:
        """Fetch one page of fossil occurrences for a taxonomic name."""
        params = {
            "base_name": base_name,
            "show": PBDB_SHOW_BLOCKS,
            "vocab": "pbdb",
            "limit": self.page_limit,
            "offset": offset,
        }
        url = f"{self.base_url}/occs/list.json?{urlencode(params)}"
        response = self._request("GET", url)
        return response.json()

    def iter_occurrences(self, *, base_name: str):
        """Yield all occurrence records for a taxonomic name, paginating as needed."""
        offset = 0
        while True:
            payload = self.list_occurrences(base_name=base_name, offset=offset)
            records = payload.get("records") or []
            if not records:
                break
            yield from records
            if len(records) < self.page_limit:
                break
            offset += self.page_limit
