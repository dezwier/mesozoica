"""Tests for Wikipedia revision-as-of lookup."""

from datetime import datetime, timezone
from unittest.mock import MagicMock

from app.services.wikipedia_service.revision import revision_as_of


def test_revision_as_of_returns_revid():
    client = MagicMock()
    client.action_api.return_value = {
        "query": {
            "pages": {
                "30467": {
                    "pageid": 30467,
                    "title": "Tyrannosaurus",
                    "revisions": [{"revid": 123456, "timestamp": "2024-06-01T12:00:00Z"}],
                }
            }
        }
    }

    revid = revision_as_of(
        client,
        title="Tyrannosaurus",
        as_of=datetime(2024, 7, 1, tzinfo=timezone.utc),
    )

    assert revid == 123456
    params = client.action_api.call_args.args[0]
    assert params["titles"] == "Tyrannosaurus"
    assert params["rvdir"] == "older"
    assert params["rvstart"] == "2024-07-01T00:00:00Z"
    assert params["redirects"] == 1


def test_revision_as_of_returns_none_when_missing():
    client = MagicMock()
    client.action_api.return_value = {
        "query": {"pages": {"-1": {"missing": True, "title": "NoSuchDino"}}}
    }

    assert (
        revision_as_of(
            client,
            title="NoSuchDino",
            as_of=datetime(2024, 7, 1, tzinfo=timezone.utc),
        )
        is None
    )


def test_revision_as_of_returns_none_when_no_revisions():
    client = MagicMock()
    client.action_api.return_value = {
        "query": {"pages": {"1": {"pageid": 1, "title": "New", "revisions": []}}}
    }

    assert (
        revision_as_of(
            client,
            title="New",
            as_of=datetime(2000, 1, 1, tzinfo=timezone.utc),
        )
        is None
    )
