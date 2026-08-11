from types import SimpleNamespace
from pathlib import Path
from unittest.mock import patch

import pytest
from sqlmodel import select

from app.crons.config import load_cron_config
from app.features.ingestion import runner as ingestion_runner
from app.features.ingestion.models.dinosaur_knowledge import (
    KNOWLEDGE_STATUS_FAILED,
    KNOWLEDGE_STATUS_PENDING,
    KNOWLEDGE_STATUS_SUCCEEDED,
    DinosaurKnowledge,
)
from app.features.specimens.public import DinosaurKnowledgeSubject
from mesozoica_ai.common import (
    Document,
    acquire_knowledge,
)
from mesozoica_ai.evaluate import RetrievalCase, load_retrieval_cases, prepare_retrieval_cases
from mesozoica_ai.evaluate import format_checkpoint_status
from mesozoica_ai.generate import QuizQuestion
from mesozoica_ai.index import index_knowledge, list_knowledge_rows


SUBJECT = DinosaurKnowledgeSubject(id=7, name="Example", wikipedia_title="Example")


def acquire_dinosaur_knowledge(
    session,
    *,
    subjects,
    retrievers,
    sources=None,
    overwrite=False,
    dry_run=False,
    max_items=None,
):
    """Test helper: wire fake retrievers into acquire_knowledge."""

    def retrieve(subject, source, metadata):
        query = subject.wikipedia_title if source == "wikipedia" else subject.name
        return retrievers[source](query, metadata=metadata)

    return acquire_knowledge(
        session,
        DinosaurKnowledge,
        subjects=subjects,
        retrieve=retrieve,
        sources=sources,
        max_items=max_items,
        overwrite=overwrite,
        dry_run=dry_run,
    )


def index_dinosaur_knowledge(session, *, config, dinosaur_names=None, **kwargs):
    return index_knowledge(
        session=session,
        model=DinosaurKnowledge,
        config=config,
        names=dinosaur_names,
        **kwargs,
    )


def format_knowledge_status(session, **kwargs):
    return format_checkpoint_status(
        list_knowledge_rows(
            session, DinosaurKnowledge, names=kwargs.pop("dinosaur_names", None)
        ),
        subject_header="DINOSAUR",
        **kwargs,
    )


class FakeWikipedia:
    def __init__(self, text="Wikipedia text"):
        self.text = text
        self.calls = 0

    def __call__(self, title):
        self.calls += 1
        return [
            Document(
                id="wiki:1:intro",
                text=self.text,
                metadata={
                    "source": "wikipedia",
                    "source_id": "1",
                    "source_version": "3",
                    "title": title,
                    "section": "Introduction",
                },
            )
        ]


class FailingOpenAlex:
    def __call__(self, query):
        raise RuntimeError("OpenAlex unavailable")


class FakeOpenAlex:
    def __call__(self, query):
        return [
            Document(
                id="openalex:W1",
                text="Paper abstract",
                metadata={
                    "source": "openalex",
                    "source_id": "W1",
                    "source_version": "2026-01-01",
                    "title": "Paper",
                    "section": "Abstract",
                },
            )
        ]


def _retrievers(*, wikipedia=None, openalex=None):
    def make(source, provider):
        def retrieve(query, *, metadata):
            if provider is None:
                raise RuntimeError(f"{source} retrieval is not configured")
            documents = []
            for document in provider(query):
                documents.append(
                    Document.model_validate(
                        {
                            **document.model_dump(mode="json"),
                            "metadata": {
                                **document.metadata.model_dump(
                                    mode="json", exclude_none=True
                                ),
                                **metadata,
                            },
                        }
                    )
                )
            return documents

        return retrieve

    return {
        "wikipedia": make("wikipedia", wikipedia),
        "openalex": make("openalex", openalex),
    }


def test_acquisition_persists_independent_source_states_and_resumes(session):
    wiki = FakeWikipedia()
    summary = acquire_dinosaur_knowledge(
        session,
        subjects=[SUBJECT],
        retrievers=_retrievers(wikipedia=wiki, openalex=FailingOpenAlex()),
    )
    rows = list(session.exec(select(DinosaurKnowledge)).all())
    by_source = {row.source: row for row in rows}

    assert summary.succeeded == 1
    assert summary.failed == 1
    assert by_source["wikipedia"].acquisition_status == KNOWLEDGE_STATUS_SUCCEEDED
    assert by_source["wikipedia"].index_status == KNOWLEDGE_STATUS_PENDING
    assert by_source["openalex"].acquisition_status == KNOWLEDGE_STATUS_FAILED
    assert by_source["wikipedia"].documents[0]["metadata"]["subject_id"] == "dinosaur:7"

    resumed = acquire_dinosaur_knowledge(
        session,
        subjects=[SUBJECT],
        retrievers=_retrievers(wikipedia=wiki, openalex=FailingOpenAlex()),
        sources=["wikipedia"],
    )
    assert resumed.skipped == 1
    assert wiki.calls == 1


def test_changed_overwrite_marks_snapshot_for_reindex(session):
    first = FakeWikipedia("old")
    acquire_dinosaur_knowledge(
        session,
        subjects=[SUBJECT],
        retrievers=_retrievers(wikipedia=first),
        sources=["wikipedia"],
    )
    snapshot = session.exec(select(DinosaurKnowledge)).one()
    snapshot.index_status = KNOWLEDGE_STATUS_SUCCEEDED
    snapshot.indexed_hash = snapshot.content_hash
    session.add(snapshot)
    session.commit()

    acquire_dinosaur_knowledge(
        session,
        subjects=[SUBJECT],
        retrievers=_retrievers(wikipedia=FakeWikipedia("new")),
        sources=["wikipedia"],
        overwrite=True,
    )
    session.expire_all()
    changed = session.exec(select(DinosaurKnowledge)).one()
    assert changed.index_status == KNOWLEDGE_STATUS_PENDING
    assert changed.indexed_hash is None


def test_unchanged_overwrite_preserves_index_checkpoint_and_records_source_hash(session):
    acquire_dinosaur_knowledge(
        session,
        subjects=[SUBJECT],
        retrievers=_retrievers(wikipedia=FakeWikipedia("same")),
        sources=["wikipedia"],
    )
    snapshot = session.exec(select(DinosaurKnowledge)).one()
    snapshot.index_status = KNOWLEDGE_STATUS_SUCCEEDED
    snapshot.indexed_hash = snapshot.content_hash
    session.add(snapshot)
    session.commit()

    acquire_dinosaur_knowledge(
        session,
        subjects=[SUBJECT],
        retrievers=_retrievers(wikipedia=FakeWikipedia("same")),
        sources=["wikipedia"],
        overwrite=True,
    )
    session.expire_all()
    unchanged = session.exec(select(DinosaurKnowledge)).one()
    assert unchanged.source_hash
    assert unchanged.index_status == KNOWLEDGE_STATUS_SUCCEEDED
    assert unchanged.indexed_hash == unchanged.content_hash


def test_running_acquisition_is_retried_after_interruption(session):
    acquire_dinosaur_knowledge(
        session,
        subjects=[SUBJECT],
        retrievers=_retrievers(wikipedia=FakeWikipedia()),
        sources=["wikipedia"],
    )
    snapshot = session.exec(select(DinosaurKnowledge)).one()
    snapshot.acquisition_status = "running"
    session.add(snapshot)
    session.commit()
    provider = FakeWikipedia()

    summary = acquire_dinosaur_knowledge(
        session,
        subjects=[SUBJECT],
        retrievers=_retrievers(wikipedia=provider),
        sources=["wikipedia"],
    )

    assert summary.succeeded == 1
    assert provider.calls == 1


def test_acquisition_dry_run_does_not_create_checkpoints(session):
    summary = acquire_dinosaur_knowledge(
        session,
        subjects=[SUBJECT],
        retrievers=_retrievers(),
        dry_run=True,
    )

    assert summary.candidates == 2
    assert summary.skipped == 2
    assert list(session.exec(select(DinosaurKnowledge)).all()) == []


def _patch_indexing(monkeypatch, *, fingerprint="pipeline-v2", fail_source=None):
    import mesozoica_ai.index.batch as workflow_module

    calls = {"ensure": 0, "recreate": 0, "prepare": [], "sync": []}

    def ensure(*, config):
        calls["ensure"] += 1

    def recreate(*, config):
        calls["recreate"] += 1

    def prepare(documents, *, config, existing=None):
        calls["prepare"].append((documents, existing))
        return SimpleNamespace(
            chunks=[
                {
                    "id": "chunk-1",
                    "document_id": "doc-1",
                    "text": "t",
                    "embedding_text": "t",
                    "metadata": {"source": "wikipedia", "source_id": "1", "title": "T"},
                    "chunk_index": 0,
                    "start_index": 0,
                    "embedding_hash": "eh",
                    "document_hash": "dh",
                    "pipeline_fingerprint": fingerprint,
                    "embedding": [0.0, 1.0],
                }
            ],
            embedded_count=1 if not existing else 0,
            reused_count=1 if existing else 0,
            chunk_count=1,
            pipeline_fingerprint=fingerprint,
        )

    def sync(embedded_chunks, *, scope, config):
        calls["sync"].append((embedded_chunks, scope))
        if scope["source"] == fail_source:
            raise RuntimeError("azure unavailable")
        return SimpleNamespace(pipeline_fingerprint=fingerprint)

    class FakeStore:
        def existing_ids(self, ids):
            return set(ids)

        def list_ids(self, filters):
            return ["chunk-1"]

    monkeypatch.setattr(workflow_module, "recreate_search_index", recreate)
    monkeypatch.setattr(workflow_module, "ensure_index", ensure)
    monkeypatch.setattr(
        workflow_module, "pipeline_fingerprint", lambda *, config: fingerprint
    )
    monkeypatch.setattr(workflow_module, "prepare_embeddings", prepare)
    monkeypatch.setattr(workflow_module, "sync_embedded_chunks", sync)
    monkeypatch.setattr(
        workflow_module,
        "build_store",
        lambda config, *, write_enabled: FakeStore(),
    )
    return calls


def test_indexing_uses_source_scope_and_recreate_resets_checkpoints(session, monkeypatch):
    acquire_dinosaur_knowledge(
        session,
        subjects=[SUBJECT],
        retrievers=_retrievers(wikipedia=FakeWikipedia()),
        sources=["wikipedia"],
    )
    calls = _patch_indexing(monkeypatch)
    summary = index_dinosaur_knowledge(
        session,
        config=SimpleNamespace(),
        recreate_index=True,
    )
    snapshot = session.exec(select(DinosaurKnowledge)).one()

    assert summary.succeeded == 1
    assert calls["recreate"] == 1
    assert snapshot.embed_status == KNOWLEDGE_STATUS_SUCCEEDED
    assert snapshot.index_status == KNOWLEDGE_STATUS_SUCCEEDED
    assert snapshot.indexed_hash == snapshot.content_hash
    assert snapshot.indexed_pipeline_fingerprint == "pipeline-v2"
    assert calls["sync"][0][1] == {
        "namespace": "mesozoica",
        "subject_id": "dinosaur:7",
        "source": "wikipedia",
    }


def test_recreate_index_rejects_partial_scope(session):
    with pytest.raises(ValueError, match="unscoped"):
        index_dinosaur_knowledge(
            session, config=SimpleNamespace(),
            dinosaur_names=["Example"], recreate_index=True,
        )


def test_indexing_continues_after_one_source_fails(session, monkeypatch):
    acquire_dinosaur_knowledge(
        session,
        subjects=[SUBJECT],
        retrievers=_retrievers(wikipedia=FakeWikipedia(), openalex=FakeOpenAlex()),
    )

    _patch_indexing(monkeypatch, fail_source="openalex")
    summary = index_dinosaur_knowledge(
        session,
        config=SimpleNamespace(),
    )
    rows = list(session.exec(select(DinosaurKnowledge)).all())
    by_source = {row.source: row for row in rows}

    assert summary.failed == 1
    assert summary.succeeded == 1
    assert by_source["openalex"].embed_status == KNOWLEDGE_STATUS_SUCCEEDED
    assert by_source["openalex"].index_status == KNOWLEDGE_STATUS_FAILED
    assert by_source["wikipedia"].embed_status == KNOWLEDGE_STATUS_SUCCEEDED
    assert by_source["wikipedia"].index_status == KNOWLEDGE_STATUS_SUCCEEDED


def test_pipeline_change_reindexes_unchanged_content(session, monkeypatch):
    acquire_dinosaur_knowledge(
        session, subjects=[SUBJECT], retrievers=_retrievers(wikipedia=FakeWikipedia()),
        sources=["wikipedia"],
    )
    _patch_indexing(monkeypatch, fingerprint="pipeline-v2")
    index_dinosaur_knowledge(
        session, config=SimpleNamespace(), sources=["wikipedia"]
    )
    calls = _patch_indexing(monkeypatch, fingerprint="pipeline-v3")
    summary = index_dinosaur_knowledge(
        session, config=SimpleNamespace(), sources=["wikipedia"]
    )
    snapshot = session.exec(select(DinosaurKnowledge)).one()
    assert summary.succeeded == 1
    assert len(calls["prepare"]) == 1
    assert len(calls["sync"]) == 1
    assert snapshot.indexed_pipeline_fingerprint == "pipeline-v3"


def test_ingest_retries_without_reembedding_after_azure_failure(session, monkeypatch):
    from mesozoica_ai.index import embed_knowledge, ingest_knowledge

    acquire_dinosaur_knowledge(
        session,
        subjects=[SUBJECT],
        retrievers=_retrievers(wikipedia=FakeWikipedia()),
        sources=["wikipedia"],
    )
    calls = _patch_indexing(monkeypatch, fingerprint="pipeline-v2", fail_source="wikipedia")
    embed_knowledge(
        session=session,
        model=DinosaurKnowledge,
        config=SimpleNamespace(),
        sources=["wikipedia"],
    )
    assert len(calls["prepare"]) == 1
    snapshot = session.exec(select(DinosaurKnowledge)).one()
    assert snapshot.embed_status == KNOWLEDGE_STATUS_SUCCEEDED
    assert snapshot.embedded_chunks

    failed = ingest_knowledge(
        session=session,
        model=DinosaurKnowledge,
        config=SimpleNamespace(),
        sources=["wikipedia"],
    )
    assert failed.failed == 1
    session.refresh(snapshot)
    assert snapshot.index_status == KNOWLEDGE_STATUS_FAILED
    prepare_count = len(calls["prepare"])

    calls2 = _patch_indexing(monkeypatch, fingerprint="pipeline-v2")
    retry = ingest_knowledge(
        session=session,
        model=DinosaurKnowledge,
        config=SimpleNamespace(),
        sources=["wikipedia"],
    )
    assert retry.succeeded == 1
    assert len(calls2["prepare"]) == 0
    assert len(calls2["sync"]) == 1
    session.refresh(snapshot)
    assert snapshot.index_status == KNOWLEDGE_STATUS_SUCCEEDED
    assert prepare_count == 1


def test_status_output_and_quiz_validation(session):
    acquire_dinosaur_knowledge(
        session,
        subjects=[SUBJECT],
        retrievers=_retrievers(wikipedia=FakeWikipedia()),
        sources=["wikipedia"],
    )
    output = format_knowledge_status(session)
    assert "Example" in output
    assert "wikipedia" in output
    assert "succeeded" in output

    with pytest.raises(ValueError, match="unique"):
        QuizQuestion(
            question="Question?",
            topic="topic",
            difficulty="easy",
            options=("same", "same", "three", "four"),
            correct_index=0,
            explanation="Because",
            source_chunk_ids=["chunk"],
        )


def test_manual_knowledge_job_is_registered_disabled():
    jobs = {job.id: job for job in load_cron_config().jobs}
    assert "dinosaur_knowledge" in jobs
    assert jobs["dinosaur_knowledge"].enabled is False
    for removed in (
        "dinosaur_knowledge_acquire",
        "dinosaur_knowledge_index",
        "dinosaur_knowledge_status",
        "dinosaur_knowledge_evaluate",
        "dinosaur_quiz_preview",
    ):
        assert removed not in jobs


def test_golden_dataset_has_three_cases_for_each_required_genus():
    path = Path(__file__).parents[1] / "rag/evaluation/dinosaur_retrieval_golden.jsonl"
    cases = load_retrieval_cases(path)
    expected = {
        "Tyrannosaurus", "Triceratops", "Velociraptor", "Stegosaurus", "Brachiosaurus",
        "Spinosaurus", "Ankylosaurus", "Allosaurus", "Diplodocus", "Iguanodon",
    }
    assert len(cases) == 30
    assert {case.subject_name for case in cases} == expected
    assert all(case.snapshot_hashes for case in cases)


def test_golden_case_refuses_changed_snapshot_hash(session):
    acquire_dinosaur_knowledge(
        session, subjects=[SUBJECT], retrievers=_retrievers(wikipedia=FakeWikipedia()),
        sources=["wikipedia"],
    )
    snapshot = session.exec(select(DinosaurKnowledge)).one()
    case = RetrievalCase(
        id="case", subject_name="Example", query="q",
        relevant_document_ids={"wiki:1:intro": 3},
        snapshot_hashes={"wikipedia": snapshot.source_hash},
    )
    prepared = prepare_retrieval_cases([case], session.exec(select(DinosaurKnowledge)).all())
    assert prepared[0].filters["subject_id"] == "dinosaur:7"
    with pytest.raises(ValueError, match="stale"):
        prepare_retrieval_cases(
            [case.model_copy(update={"snapshot_hashes": {"wikipedia": "changed"}})],
            session.exec(select(DinosaurKnowledge)).all(),
        )


def test_knowledge_runner_routes_scope_and_control_flags(monkeypatch):
    captured = {}

    def fake_run(**kwargs):
        captured.update(kwargs)
        return 0

    monkeypatch.setattr(ingestion_runner.dinosaur_knowledge, "run_knowledge_job", fake_run)

    result = ingestion_runner._run_dinosaur_knowledge(
        {
            "dinos": ["Example"],
            "sources": "Wikipedia,OpenAlex",
            "max_items": "2",
            "overwrite": True,
            "dry_run": True,
            "recreate_index": True,
        }
    )

    assert result == 0
    assert captured == {
        "dinos": ["Example"],
        "sources": ["wikipedia", "openalex"],
        "max_items": 2,
        "overwrite": True,
        "dry_run": True,
        "recreate_index": True,
    }
