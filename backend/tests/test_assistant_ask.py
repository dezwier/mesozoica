"""Unit tests for the field-assistant ask use case."""

from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest

from app.features.assistant.application.ask import ask_question, select_references
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


def test_select_references_prefers_cited_chunk_ids() -> None:
    records = [
        {
            "id": "c1",
            "document_id": "wiki-1",
            "source": "wikipedia",
            "title": "Abrosaurus",
            "section": "Paleobiology",
            "source_url": "https://en.wikipedia.org/wiki/Abrosaurus#Paleobiology",
            "text": "Chunk one about size.",
        },
        {
            "id": "c2",
            "document_id": "oa-1",
            "source": "openalex",
            "title": "Paper A",
            "source_url": "https://doi.org/10.1/a",
            "text": "Chunk two about diet.",
        },
        {
            "id": "c3",
            "document_id": "oa-2",
            "source": "openalex",
            "title": "Paper B",
            "source_url": "https://doi.org/10.1/b",
            "text": "Chunk three unused.",
        },
    ]
    refs = select_references(records, cited_ids=["c2", "c1"])
    assert refs == [
        SourceLink(
            title="Paper A",
            url="https://doi.org/10.1/a",
            kind="openalex",
            text="Chunk two about diet.",
        ),
        SourceLink(
            title="Abrosaurus — Paleobiology",
            url="https://en.wikipedia.org/wiki/Abrosaurus#Paleobiology",
            kind="wikipedia",
            text="Chunk one about size.",
        ),
    ]


def test_select_references_falls_back_to_retrieval_order() -> None:
    records = [
        {
            "id": "c1",
            "source": "openalex",
            "title": "Only Paper",
            "source_url": "https://doi.org/10.1/a",
            "text": "Body.",
        },
        {
            "id": "c2",
            "source": "wikipedia",
            "title": "",
            "source_url": "https://en.wikipedia.org/wiki/Empty",
            "text": "Wiki body.",
        },
    ]
    refs = select_references(records, cited_ids=[])
    assert refs == [
        SourceLink(
            title="Only Paper",
            url="https://doi.org/10.1/a",
            kind="openalex",
            text="Body.",
        ),
        SourceLink(
            title="Source",
            url="https://en.wikipedia.org/wiki/Empty",
            kind="wikipedia",
            text="Wiki body.",
        ),
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
            text="Abrosaurus ate plants.",
        ),
        _chunk(
            chunk_id="c2",
            document_id="oa-1",
            source="openalex",
            title="Diet of Abrosaurus",
            source_url="https://doi.org/10.1/diet",
            text="Herbivore evidence.",
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
    assert retrieve.call_args.kwargs["filters"] == {"namespace": "mesozoica"}
    prompt.assert_called_once()
    assert result.answer == "Abrosaurus was a herbivore."
    assert result.sources == [
        SourceLink(
            title="Abrosaurus — Diet",
            url="https://en.wikipedia.org/wiki/Abrosaurus#Diet",
            kind="wikipedia",
            text="Abrosaurus ate plants.",
        ),
    ]


def test_ask_question_scopes_filters_when_subject_id_set() -> None:
    grounded = GroundedAnswer(answer="Scoped.", source_chunk_ids=["c1"])
    config = MagicMock()
    with (
        patch(
            "app.features.assistant.application.ask.embed_query",
            return_value=[0.1],
        ) as embed,
        patch(
            "app.features.assistant.application.ask.retrieve_chunks",
            return_value=[],
        ) as retrieve,
        patch(
            "app.features.assistant.application.ask.prompt_rag",
            return_value=grounded,
        ) as prompt,
    ):
        ask_question(
            "How big?",
            subject_id="42",
            subject_name="Abrosaurus",
            config=config,
        )

    assert embed.call_args.args[0] == "About Abrosaurus: How big?"
    assert retrieve.call_args.kwargs["filters"] == {
        "namespace": "mesozoica",
        "subject_id": "dinosaur:42",
    }
    assert retrieve.call_args.args[0] == "About Abrosaurus: How big?"
    assert prompt.call_args.kwargs["query"] == "About Abrosaurus: How big?"
    assert prompt.call_args.kwargs["application_context"] == {
        "selected_dinosaur": "Abrosaurus",
        "subject_id": "dinosaur:42",
    }
    assert "selected_dinosaur" in prompt.call_args.kwargs["instructions"]


def test_ask_question_keeps_prefixed_subject_id() -> None:
    grounded = GroundedAnswer(answer="Scoped.", source_chunk_ids=["c1"])
    config = MagicMock()
    with (
        patch(
            "app.features.assistant.application.ask.embed_query",
            return_value=[0.1],
        ),
        patch(
            "app.features.assistant.application.ask.retrieve_chunks",
            return_value=[],
        ) as retrieve,
        patch(
            "app.features.assistant.application.ask.prompt_rag",
            return_value=grounded,
        ),
    ):
        ask_question("How big?", subject_id="dinosaur:7", config=config)

    assert retrieve.call_args.kwargs["filters"]["subject_id"] == "dinosaur:7"


def test_ask_question_does_not_duplicate_name_in_query() -> None:
    grounded = GroundedAnswer(answer="Scoped.", source_chunk_ids=["c1"])
    config = MagicMock()
    with (
        patch(
            "app.features.assistant.application.ask.embed_query",
            return_value=[0.1],
        ),
        patch(
            "app.features.assistant.application.ask.retrieve_chunks",
            return_value=[],
        ) as retrieve,
        patch(
            "app.features.assistant.application.ask.prompt_rag",
            return_value=grounded,
        ) as prompt,
    ):
        ask_question(
            "How big was Abrosaurus?",
            subject_id="42",
            subject_name="Abrosaurus",
            config=config,
        )

    assert retrieve.call_args.args[0] == "How big was Abrosaurus?"
    assert prompt.call_args.kwargs["query"] == "How big was Abrosaurus?"


def test_ask_question_rejects_blank() -> None:
    with pytest.raises(ValueError, match="blank"):
        ask_question("   ", config=MagicMock())
