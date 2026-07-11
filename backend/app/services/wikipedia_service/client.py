"""HTTP client for Wikipedia Action API and REST API."""

from __future__ import annotations

import time
from typing import Any
from urllib.parse import quote

import httpx
from tenacity import retry, retry_if_exception_type, stop_after_attempt, wait_exponential

from app.core.config import settings

_RETRYABLE = (httpx.HTTPStatusError, httpx.TransportError)


class WikipediaClient:
    """Polite Wikipedia API client with rate limiting and retries."""

    def __init__(
        self,
        *,
        base_url: str | None = None,
        user_agent: str | None = None,
        delay_ms: int | None = None,
    ) -> None:
        self.base_url = (base_url or settings.wikipedia_base_url).rstrip("/")
        self.user_agent = user_agent or settings.wikipedia_user_agent
        self.delay_s = (delay_ms if delay_ms is not None else settings.wikipedia_request_delay_ms) / 1000.0
        self._last_request_at = 0.0
        self._http = httpx.Client(
            headers={"User-Agent": self.user_agent},
            timeout=httpx.Timeout(30.0, connect=10.0),
            follow_redirects=True,
        )

    def close(self) -> None:
        self._http.close()

    def __enter__(self) -> WikipediaClient:
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

    def action_api(self, params: dict[str, Any]) -> dict[str, Any]:
        """Call the MediaWiki Action API."""
        query = {"format": "json", **params}
        url = f"{self.base_url}/w/api.php"
        response = self._request("GET", url, params=query)
        return response.json()

    def rest_get_json(self, path: str) -> dict[str, Any]:
        """GET a REST API endpoint returning JSON."""
        url = f"{self.base_url}{path}"
        response = self._request("GET", url, headers={"Accept": "application/json"})
        return response.json()

    def page_bare(self, title: str) -> dict[str, Any]:
        encoded = quote(title.replace(" ", "_"), safe="")
        return self.rest_get_json(f"/w/rest.php/v1/page/{encoded}/bare")

    def page_with_html(self, title: str) -> dict[str, Any]:
        encoded = quote(title.replace(" ", "_"), safe="")
        return self.rest_get_json(f"/w/rest.php/v1/page/{encoded}/with_html")
