"""Unit tests for assistant knowledge subject/source browser use cases."""

from __future__ import annotations

from app.features.assistant.application.list_sources import list_subject_sources
from app.features.assistant.application.list_subjects import list_indexed_subjects
from app.features.assistant.schemas import (
    KnowledgeSourceGroup,
    KnowledgeSourceItem,
    KnowledgeSubject,
)
from app.features.ingestion.models import (
    KNOWLEDGE_STATUS_PENDING,
    KNOWLEDGE_STATUS_SUCCEEDED,
    DinosaurKnowledgeSource,
)
from mesozoica_ai.common import Document, SourceMetadata


def test_list_indexed_subjects_distinct_succeeded_only(session) -> None:
    session.add(
        DinosaurKnowledgeSource(
            subject_kind="dinosaur",
            subject_id="1",
            subject_name="Abrosaurus",
            source="wikipedia",
            index_status=KNOWLEDGE_STATUS_SUCCEEDED,
        )
    )
    session.add(
        DinosaurKnowledgeSource(
            subject_kind="dinosaur",
            subject_id="1",
            subject_name="Abrosaurus",
            source="openalex",
            index_status=KNOWLEDGE_STATUS_SUCCEEDED,
        )
    )
    session.add(
        DinosaurKnowledgeSource(
            subject_kind="dinosaur",
            subject_id="2",
            subject_name="Zuniceratops",
            source="wikipedia",
            index_status=KNOWLEDGE_STATUS_PENDING,
        )
    )
    session.add(
        DinosaurKnowledgeSource(
            subject_kind="dinosaur",
            subject_id="3",
            subject_name="Tyrannosaurus",
            source="wikipedia",
            index_status=KNOWLEDGE_STATUS_SUCCEEDED,
        )
    )
    session.commit()

    subjects = list_indexed_subjects(session)
    assert subjects == [
        KnowledgeSubject(id="1", name="Abrosaurus"),
        KnowledgeSubject(id="3", name="Tyrannosaurus"),
    ]


def test_list_subject_sources_groups_and_dedupes(session, monkeypatch) -> None:
    wiki = DinosaurKnowledgeSource(
        subject_kind="dinosaur",
        subject_id="7",
        subject_name="Example",
        source="wikipedia",
        index_status=KNOWLEDGE_STATUS_SUCCEEDED,
    )
    oa = DinosaurKnowledgeSource(
        subject_kind="dinosaur",
        subject_id="7",
        subject_name="Example",
        source="openalex",
        index_status=KNOWLEDGE_STATUS_SUCCEEDED,
    )
    session.add(wiki)
    session.add(oa)
    session.commit()
    session.refresh(wiki)
    session.refresh(oa)

    docs_by_source = {
        wiki.id: [
            Document(
                id="wiki:1:intro",
                text="Intro text",
                metadata=SourceMetadata(
                    source="wikipedia",
                    source_id="1",
                    title="Example",
                    section="Introduction",
                    source_url="https://en.wikipedia.org/wiki/Example",
                ),
            ),
            Document(
                id="wiki:1:diet",
                text="Diet text",
                metadata=SourceMetadata(
                    source="wikipedia",
                    source_id="1",
                    title="Example",
                    section="Diet",
                    source_url="https://en.wikipedia.org/wiki/Example#Diet",
                ),
            ),
        ],
        oa.id: [
            Document(
                id="oa:a:abs",
                text="Paper abstract",
                metadata=SourceMetadata(
                    source="openalex",
                    source_id="W123",
                    title="Paper One",
                    source_url="https://doi.org/10.1/a",
                ),
            ),
            Document(
                id="oa:a:body",
                text="Paper body",
                metadata=SourceMetadata(
                    source="openalex",
                    source_id="W123",
                    title="Paper One",
                    source_url="https://doi.org/10.1/a",
                ),
            ),
            Document(
                id="oa:b:abs",
                text="Other paper",
                metadata=SourceMetadata(
                    source="openalex",
                    source_id="W456",
                    title="Paper Two",
                    source_url="https://doi.org/10.1/b",
                ),
            ),
        ],
    }

    class FakeRepo:
        def list_documents(self, source_row):
            return docs_by_source.get(source_row.id, [])

    monkeypatch.setattr(
        "app.features.assistant.application.list_sources.dinosaur_knowledge_repo",
        lambda _session: FakeRepo(),
    )

    result = list_subject_sources(session, "7")
    assert result is not None
    assert result.subject_id == "7"
    assert result.subject_name == "Example"
    assert result.groups == [
        KnowledgeSourceGroup(
            kind="wikipedia",
            items=[
                KnowledgeSourceItem(
                    title="Example",
                    url="https://en.wikipedia.org/wiki/Example",
                    kind="wikipedia",
                )
            ],
        ),
        KnowledgeSourceGroup(
            kind="openalex",
            items=[
                KnowledgeSourceItem(
                    title="Paper One",
                    url="https://doi.org/10.1/a",
                    kind="openalex",
                ),
                KnowledgeSourceItem(
                    title="Paper Two",
                    url="https://doi.org/10.1/b",
                    kind="openalex",
                ),
            ],
        ),
    ]


def test_list_subject_sources_missing_returns_none(session) -> None:
    assert list_subject_sources(session, "missing") is None
