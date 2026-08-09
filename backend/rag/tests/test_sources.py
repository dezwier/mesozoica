import httpx

from mesozoica_ai.sources import OpenAlexSource, WikipediaSource, reconstruct_abstract
from mesozoica_ai.sources.http import RetryingJsonClient


class StubJsonClient:
    def __init__(self, payload):
        self.payload = payload
        self.calls = []

    def get(self, url, *, params, headers):
        self.calls.append((url, params, headers))
        return self.payload


def test_wikipedia_returns_sections_with_revision_metadata():
    client = StubJsonClient(
        {
            "query": {
                "pages": [
                    {
                        "pageid": 42,
                        "title": "Example animal",
                        "extract": "Lead text.\n\n== Description ==\nBody text.\n\n== References ==\nIgnore me.",
                        "revisions": [{"revid": 7, "timestamp": "2026-01-02T00:00:00Z"}],
                    }
                ]
            }
        }
    )

    documents = WikipediaSource(user_agent="test@example.com", client=client).fetch(
        "Example animal"
    )

    assert [document.metadata["section"] for document in documents] == [
        "Introduction",
        "Description",
    ]
    assert documents[0].metadata["source_version"] == "7"
    assert documents[1].id == "wikipedia:42:description"


def test_openalex_reconstructs_and_filters_abstracts():
    assert reconstruct_abstract({"world": [1], "Hello": [0]}) == "Hello world"
    client = StubJsonClient(
        {
            "results": [
                {
                    "id": "https://openalex.org/W1",
                    "display_name": "A useful paper",
                    "abstract_inverted_index": {"fossil": [1], "A": [0]},
                    "is_retracted": False,
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
                    "abstract_inverted_index": {"bad": [0]},
                    "is_retracted": True,
                },
            ]
        }
    )

    documents = OpenAlexSource(
        api_key="key", user_agent="test@example.com", client=client
    ).search("Example", limit=10)

    assert len(documents) == 1
    assert documents[0].id == "openalex:W1"
    assert documents[0].text == "A fossil"
    assert documents[0].metadata["authors"] == ["A. Author"]
    assert client.calls[0][1]["per_page"] == 10


def test_source_http_client_retries_throttling_with_retry_after():
    request = httpx.Request("GET", "https://example.test")
    responses = [
        httpx.Response(429, headers={"Retry-After": "0"}, request=request),
        httpx.Response(200, json={"ok": True}, request=request),
    ]

    class Client:
        def get(self, *args, **kwargs):
            return responses.pop(0)

    delays = []
    result = RetryingJsonClient(
        Client(), attempts=2, sleeper=delays.append
    ).get("https://example.test", params={}, headers={})

    assert result == {"ok": True}
    assert delays == [0.0]
