"""Unit tests for the field-assistant ask use case."""

from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest

from app.features.assistant.application.ask import ask_question, select_sources
from app.features.assistant.schemas import SourceLink
from mesozoica_ai.common.metadata import SourceMetadata
from mesozoica_ai.common.models import RetrievedChunk
from mesozoica_ai.generate import GroundedAnswer


def _chunk(
    *,
    chunk_id: str,
    document_id: str,
    source: str,
    title: str,
    source_url: str | None,
    section: str | None = None,
    text: str = "evidence",
) -> RetrievedChunk:
    return RetrievedChunk(
        id=chunk_id,
        document_id=document_id,
        text=text,
        metadata=SourceMetadata(
            source=source,
            source_id=f"{source}:{document_id}",
            title=title,
            section=section,
            source_url=source_url,
        ),
        score=1.0,
    )


def test_select_sources_keeps_retrieval_order_mixed_wiki_and_papers() -> None:
    records = [
        {
            "document_id": "wiki-1",
            "source": "wikipedia",
            "title": "Abrosaurus",
            "section": "Paleobiology",
            "source_url": "https://en.wikipedia.org/wiki/Abrosaurus#Paleobiology",
        },
        {
            "document_id": "oa-1",
            "source": "openalex",
            "title": "Paper A",
            "source_url": "https://doi.org/10.1/a",
        },
        {
            "document_id": "oa-1",
            "source": "openalex",
            "title": "Paper A again",
            "source_url": "https://doi.org/10.1/a",
        },
        {
            "document_id": "wiki-2",
            "source": "wikipedia",
            "title": "Abrosaurus",
            "section": "Introduction",
            "source_url": "https://en.wikipedia.org/wiki/Abrosaurus",
        },
        {
            "document_id": "oa-2",
            "source": "openalex",
            "title": "Paper B",
            "source_url": "https://doi.org/10.1/b",
        },
        {
            "document_id": "oa-3",
            "source": "openalex",
            "title": "Paper C",
            "source_url": "https://doi.org/10.1/c",
        },
    ]
    sources = select_sources(records)
    assert sources == [
        SourceLink(
            title="Abrosaurus — Paleobiology",
            url="https://en.wikipedia.org/wiki/Abrosaurus#Paleobiology",
            kind="wikipedia",
        ),
        SourceLink(title="Paper A", url="https://doi.org/10.1/a", kind="openalex"),
        SourceLink(
            title="Abrosaurus",
            url="https://en.wikipedia.org/wiki/Abrosaurus",
            kind="wikipedia",
        ),
    ]


def test_select_sources_skips_blank_titles() -> None:
    records = [
        {
            "document_id": "oa-1",
            "source": "openalex",
            "title": "Only Paper",
            "source_url": "https://doi.org/10.1/a",
        },
        {
            "document_id": "wiki-2",
            "source": "wikipedia",
            "title": "",
            "source_url": "https://en.wikipedia.org/wiki/Empty",
        },
    ]
    sources = select_sources(records)
    assert sources == [
        SourceLink(title="Only Paper", url="https://doi.org/10.1/a", kind="openalex"),
    ]


def test_ask_question_happy_path() -> None:
    chunks = [
        _chunk(
            chunk_id="c1",
            document_id="wiki-1",
            source="wikipedia",
            title="Abrosaurus",
            section="Diet",
            source_url="https://en.wikipedia.org/wiki/Abrosaurus#Diet",
        ),
        _chunk(
            chunk_id="c2",
            document_id="oa-1",
            source="openalex",
            title="Diet of Abrosaurus",
            source_url="https://doi.org/10.1/diet",
        ),
    ]
    grounded = GroundedAnswer(answer="Abrosaurus was a herbivore.", source_chunk_ids=["c1"])
    config = MagicMock()

    with (
        patch(
            "app.features.assistant.application.ask.embed_query",
            return_value=[0.1, 0.2],
        ) as embed,
        patch(
            "app.features.assistant.application.ask.retrieve_chunks",
            return_value=chunks,
        ) as retrieve,
        patch(
            "app.features.assistant.application.ask.prompt_rag",
            return_value=grounded,
        ) as prompt,
    ):
        result = ask_question("What did Abrosaurus eat?", config=config)

    embed.assert_called_once()
    retrieve.assert_called_once()
    prompt.assert_called_once()
    assert result.answer == "Abrosaurus was a herbivore."
    assert result.sources == [
        SourceLink(
            title="Abrosaurus — Diet",
            url="https://en.wikipedia.org/wiki/Abrosaurus#Diet",
            kind="wikipedia",
        ),
        SourceLink(
            title="Diet of Abrosaurus",
            url="https://doi.org/10.1/diet",
            kind="openalex",
        ),
    ]


def test_ask_question_rejects_blank() -> None:
    with pytest.raises(ValueError, match="blank"):
        ask_question("   ", config=MagicMock())
