import httpx
import pytest
from datetime import datetime, timezone
from types import SimpleNamespace

from mesozoica_ai.common.errors import RateLimitedError, SourceFetchError
from mesozoica_ai.common import (
    acquisition_needed,
    begin_acquisition,
    complete_acquisition,
    fail_acquisition,
)
from mesozoica_ai.sources.openalex import _retrieve as retrieve_openalex_with_client
from mesozoica_ai.sources.openalex import _retrieve_documents as retrieve_openalex_documents
from mesozoica_ai.sources.http import RetryingJsonClient
from mesozoica_ai.sources.http import _retry_after_seconds


class StubJsonClient:
    def __init__(self, payload, *, text_by_url=None):
        self.payload = payload
        self.text_by_url = text_by_url or {}
        self.calls = []
        self.text_calls = []

    def get(self, url, *, params, headers, source="unknown"):
        self.calls.append((url, params, headers, source))
        return self.payload

    def get_text(self, url, *, params, headers, source="unknown"):
        self.text_calls.append((url, params, headers, source))
        if url not in self.text_by_url:
            raise SourceFetchError(f"{source} returned HTTP 404")
        return self.text_by_url[url]


SAMPLE_TEI = """<?xml version="1.0" encoding="UTF-8"?>
<TEI xmlns="http://www.tei-c.org/ns/1.0">
  <teiHeader>
    <profileDesc>
      <abstract>
        <p>First abstract sentence.</p>
        <p>Second abstract sentence.</p>
      </abstract>
    </profileDesc>
  </teiHeader>
  <text>
    <body>
      <div>
        <head>Introduction</head>
        <p>Intro paragraph one.</p>
        <p>Intro paragraph two.</p>
        <div>
          <head>Background</head>
          <p>Nested background text.</p>
        </div>
      </div>
      <div type="references">
        <head>References</head>
        <p>Should be skipped.</p>
      </div>
    </body>
  </text>
</TEI>
"""


def test_openalex_fulltext_splits_tei_sections_and_preserves_paragraphs():
    work_url = "https://content.openalex.org/works/W9.grobid-xml"
    client = StubJsonClient(
        {
            "results": [
                {
                    "id": "https://openalex.org/W9",
                    "display_name": "Full paper",
                    "is_retracted": False,
                    "has_content": {"pdf": True, "grobid_xml": True},
                    "content_urls": {"grobid_xml": work_url},
                    "authorships": [{"author": {"display_name": "A. Author"}}],
                    "primary_location": {"source": {"display_name": "Journal"}},
                    "doi": "https://doi.org/10/example",
                    "publication_year": 2024,
                    "publication_date": "2024-01-02",
                    "updated_date": "2026-01-01",
                    "cited_by_count": 12,
                    "relevance_score": 99.0,
                },
                {
                    "id": "https://openalex.org/W2",
                    "display_name": "Retracted",
                    "is_retracted": True,
                    "has_content": {"grobid_xml": True},
                },
            ]
        },
        text_by_url={work_url: SAMPLE_TEI},
    )

    documents = retrieve_openalex_with_client(
        "Example",
        api_key="key",
        user_agent="test@example.com",
        limit=5,
        exclude_work_ids=set(),
        client=client,
    )

    assert [document.metadata.section for document in documents] == [
        "Abstract",
        "Introduction",
        "Background",
    ]
    assert documents[0].text == "First abstract sentence.\n\nSecond abstract sentence."
    assert documents[1].text == "Intro paragraph one.\n\nIntro paragraph two."
    assert documents[2].metadata.section_path == ["Introduction", "Background"]
    assert documents[1].id == "openalex:W9:section:1:introduction"
    assert documents[0].metadata.content_format == "grobid_xml"
    assert documents[0].metadata.authors == ["A. Author"]
    assert "has_content.grobid_xml:true" in client.calls[0][1]["filter"]
    assert client.calls[0][1]["per_page"] == 20
    assert client.text_calls[0][0] == work_url
    assert client.text_calls[0][1]["api_key"] == "key"


def test_openalex_fulltext_failure_skips_work():
    client = StubJsonClient(
        {
            "results": [
                {
                    "id": "https://openalex.org/W3",
                    "display_name": "Broken TEI paper",
                    "is_retracted": False,
                    "has_content": {"grobid_xml": True},
                    "authorships": [],
                    "primary_location": {},
                }
            ]
        }
    )
    documents = retrieve_openalex_with_client(
        "Example",
        api_key="key",
        user_agent="test@example.com",
        limit=5,
        exclude_work_ids=set(),
        client=client,
    )
    assert documents == []
    assert len(client.text_calls) == 1


def test_openalex_skips_excluded_work_ids_and_returns_empty():
    client = StubJsonClient(
        {
            "results": [
                {
                    "id": "https://openalex.org/W9",
                    "display_name": "Already have this",
                    "is_retracted": False,
                    "has_content": {"grobid_xml": True},
                    "authorships": [],
                    "primary_location": {},
                }
            ]
        },
        text_by_url={},
    )
    documents = retrieve_openalex_with_client(
        "Example",
        api_key="key",
        user_agent="test@example.com",
        limit=5,
        exclude_work_ids={"W9"},
        client=client,
    )
    assert documents == []
    assert client.text_calls == []


def test_http_get_text_decompresses_raw_gzip_bodies():
    import gzip

    request = httpx.Request("GET", "https://example.test/tei")
    payload = gzip.compress(b"<TEI><text><body><p>Hi</p></body></text></TEI>")

    class Client:
        def get(self, *args, **kwargs):
            return httpx.Response(
                200,
                content=payload,
                headers={"content-type": "application/gzip"},
                request=request,
            )

    text = RetryingJsonClient(Client(), attempts=1).get_text(
        "https://example.test/tei", params={}, headers={}, source="openalex-content"
    )
    assert "<TEI>" in text
    assert "Hi" in text


def test_acquisition_checkpoint_helpers_preserve_or_invalidate_index_state():
    checkpoint = SimpleNamespace(
        source_version=None, source_hash=None, content_hash=None,
        embedded_hash="old",
        embedded_pipeline_fingerprint="pipeline",
        indexed_hash="old", indexed_pipeline_fingerprint="pipeline",
        acquisition_status="pending", embed_status="succeeded",
        index_status="succeeded",
        acquisition_attempts=0, acquisition_error=None,
        embed_error=None, index_error=None,
        acquisition_started_at=None, acquisition_finished_at=None,
        updated_at=datetime.now(timezone.utc),
    )
    begin_acquisition(checkpoint)
    assert checkpoint.acquisition_status == "running"
    assert checkpoint.acquisition_attempts == 1

    first = SimpleNamespace(
        content_hash="a" * 64,
        source_hash="b" * 64,
        source_version=None,
    )
    assert complete_acquisition(checkpoint, first) is True
    assert checkpoint.embed_status == "pending"
    assert checkpoint.index_status == "pending"
    assert acquisition_needed(checkpoint) is False

    checkpoint.embed_status = "succeeded"
    checkpoint.embedded_hash = checkpoint.content_hash
    checkpoint.embedded_pipeline_fingerprint = "pipeline"
    checkpoint.index_status = "succeeded"
    checkpoint.indexed_hash = checkpoint.content_hash
    checkpoint.indexed_pipeline_fingerprint = "pipeline"
    begin_acquisition(checkpoint)
    assert complete_acquisition(checkpoint, first) is False
    assert checkpoint.embed_status == "succeeded"
    assert checkpoint.index_status == "succeeded"

    begin_acquisition(checkpoint)
    fail_acquisition(checkpoint, RuntimeError("temporary"))
    assert checkpoint.acquisition_status == "failed"
    assert checkpoint.acquisition_error == "temporary"


def test_source_http_client_stops_cleanly_on_429():
    request = httpx.Request("GET", "https://example.test")

    class Client:
        calls = 0

        def get(self, *args, **kwargs):
            self.calls += 1
            return httpx.Response(429, headers={"Retry-After": "30"}, request=request)

    delays = []
    client = Client()
    with pytest.raises(RateLimitedError, match="HTTP 429"):
        RetryingJsonClient(client, attempts=4, sleeper=delays.append).get(
            "https://example.test", params={}, headers={}, source="openalex-content"
        )

    assert client.calls == 1
    assert delays == []


def test_http_date_retry_after_and_normal_4xx_is_not_retried():
    now = datetime(2026, 1, 1, tzinfo=timezone.utc)
    assert _retry_after_seconds("Thu, 01 Jan 2026 00:00:03 GMT", now=now) == 3
    request = httpx.Request("GET", "https://example.test")

    class Client:
        calls = 0
        def get(self, *args, **kwargs):
            self.calls += 1
            return httpx.Response(404, request=request)

    client = Client()
    with pytest.raises(Exception, match="HTTP 404"):
        RetryingJsonClient(client, attempts=4, sleeper=lambda _: None).get(
            "https://example.test", params={}, headers={}, source="test"
        )
    assert client.calls == 1


def test_http_context_manager_closes_only_owned_client(monkeypatch):
    closed = []

    class Owned:
        def __init__(self, **kwargs): pass
        def close(self): closed.append("owned")

    monkeypatch.setattr(httpx, "Client", Owned)
    with RetryingJsonClient():
        pass
    assert closed == ["owned"]

    class Borrowed:
        def close(self): closed.append("borrowed")

    with RetryingJsonClient(Borrowed()):
        pass
    assert closed == ["owned"]


def test_public_openalex_owns_and_closes_client(monkeypatch):
    events = []

    class Client:
        def __init__(self, **kwargs):
            events.append(("created", kwargs))

        def __enter__(self):
            return self

        def __exit__(self, *args):
            events.append(("closed", {}))

    monkeypatch.setattr("mesozoica_ai.sources.openalex.RetryingJsonClient", Client)
    monkeypatch.setattr(
        "mesozoica_ai.sources.openalex._retrieve", lambda *args, **kwargs: []
    )
    assert (
        retrieve_openalex_documents(
            "Example",
            user_agent="test@example.com",
            timeout=3,
            api_key="key",
        )
        == []
    )
    assert events == [
        ("created", {"connect_timeout_seconds": 3, "read_timeout_seconds": 3}),
        ("closed", {}),
    ]
