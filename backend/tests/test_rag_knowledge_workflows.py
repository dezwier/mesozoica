import hashlib
import json
import contextlib
from types import SimpleNamespace
from pathlib import Path

import pytest
from sqlmodel import select

from app.crons.config import load_cron_config
from app.features.ingestion import runner as ingestion_runner
from app.features.ingestion.models.rag_source_snapshot import (
    RAG_STATUS_FAILED,
    RAG_STATUS_PENDING,
    RAG_STATUS_SUCCEEDED,
    RagSourceSnapshot,
)
from app.features.specimens.public import DinosaurKnowledgeSubject
from mesozoica_ai.common import Document
from mesozoica_ai.evaluate import RetrievalCase, load_retrieval_cases, prepare_retrieval_cases
from mesozoica_ai.evaluate import format_checkpoint_status
from mesozoica_ai.generate import QuizQuestion
from mesozoica_ai.index import index_knowledge
from mesozoica_ai.sources import SqlSnapshotStore, acquire_knowledge, RetrievedDocuments


SUBJECT = DinosaurKnowledgeSubject(id=7, name="Example", wikipedia_title="Example")


def _store(session):
    return SqlSnapshotStore(session, model=RagSourceSnapshot)


def acquire_dinosaur_knowledge(session, **kwargs):
    return acquire_knowledge(store=_store(session), **kwargs)


def index_dinosaur_knowledge(session, *, config, dinosaur_names=None, **kwargs):
    return index_knowledge(
        config=config, store=_store(session), names=dinosaur_names, **kwargs
    )


def format_knowledge_status(session, **kwargs):
    return format_checkpoint_status(
        _store(session).list_all(names=kwargs.pop("dinosaur_names", None)),
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
            serialized = [document.model_dump(mode="json") for document in documents]
            content_hash = hashlib.sha256(
                json.dumps(serialized, sort_keys=True).encode()
            ).hexdigest()
            return RetrievedDocuments(
                source=source,
                documents=documents,
                content_hash=content_hash,
                source_hash=hashlib.sha256(source.encode()).hexdigest(),
                source_version="3" if source == "wikipedia" else "2026-01-01",
            )

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
    rows = list(session.exec(select(RagSourceSnapshot)).all())
    by_source = {row.source: row for row in rows}

    assert summary.succeeded == 1
    assert summary.failed == 1
    assert by_source["wikipedia"].acquisition_status == RAG_STATUS_SUCCEEDED
    assert by_source["wikipedia"].index_status == RAG_STATUS_PENDING
    assert by_source["openalex"].acquisition_status == RAG_STATUS_FAILED
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
    snapshot = session.exec(select(RagSourceSnapshot)).one()
    snapshot.index_status = RAG_STATUS_SUCCEEDED
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
    changed = session.exec(select(RagSourceSnapshot)).one()
    assert changed.index_status == RAG_STATUS_PENDING
    assert changed.indexed_hash is None


def test_unchanged_overwrite_preserves_index_checkpoint_and_records_source_hash(session):
    acquire_dinosaur_knowledge(
        session,
        subjects=[SUBJECT],
        retrievers=_retrievers(wikipedia=FakeWikipedia("same")),
        sources=["wikipedia"],
    )
    snapshot = session.exec(select(RagSourceSnapshot)).one()
    snapshot.index_status = RAG_STATUS_SUCCEEDED
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
    unchanged = session.exec(select(RagSourceSnapshot)).one()
    assert unchanged.source_hash
    assert unchanged.index_status == RAG_STATUS_SUCCEEDED
    assert unchanged.indexed_hash == unchanged.content_hash


def test_running_acquisition_is_retried_after_interruption(session):
    acquire_dinosaur_knowledge(
        session,
        subjects=[SUBJECT],
        retrievers=_retrievers(wikipedia=FakeWikipedia()),
        sources=["wikipedia"],
    )
    snapshot = session.exec(select(RagSourceSnapshot)).one()
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
    assert list(session.exec(select(RagSourceSnapshot)).all()) == []


def _patch_indexing(monkeypatch, *, fingerprint="pipeline-v2", fail_source=None):
    import mesozoica_ai.index.batch as workflow_module

    calls = {"ensure": 0, "recreate": 0, "sync": []}

    def ensure(*, config):
        calls["ensure"] += 1

    def recreate(*, config):
        calls["recreate"] += 1

    def sync(documents, *, scope, config):
        calls["sync"].append((documents, scope))
        if scope["source"] == fail_source:
            raise RuntimeError("embedding unavailable")
        return SimpleNamespace(pipeline_fingerprint=fingerprint)

    monkeypatch.setattr(workflow_module, "recreate_search_index", recreate)
    monkeypatch.setattr(workflow_module, "ensure_index", ensure)
    monkeypatch.setattr(
        workflow_module, "pipeline_fingerprint", lambda *, config: fingerprint
    )
    monkeypatch.setattr(workflow_module, "sync_documents", sync)
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
    snapshot = session.exec(select(RagSourceSnapshot)).one()

    assert summary.succeeded == 1
    assert calls["recreate"] == 1
    assert snapshot.index_status == RAG_STATUS_SUCCEEDED
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
    rows = list(session.exec(select(RagSourceSnapshot)).all())
    by_source = {row.source: row for row in rows}

    assert summary.failed == 1
    assert summary.succeeded == 1
    assert by_source["openalex"].index_status == RAG_STATUS_FAILED
    assert by_source["wikipedia"].index_status == RAG_STATUS_SUCCEEDED


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
    snapshot = session.exec(select(RagSourceSnapshot)).one()
    assert summary.succeeded == 1
    assert len(calls["sync"]) == 1
    assert snapshot.indexed_pipeline_fingerprint == "pipeline-v3"


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


def test_manual_knowledge_jobs_are_registered_disabled():
    jobs = {job.id: job for job in load_cron_config().jobs}
    for job_id in (
        "dinosaur_knowledge_acquire",
        "dinosaur_knowledge_index",
        "dinosaur_knowledge_status",
        "dinosaur_knowledge_evaluate",
        "dinosaur_quiz_preview",
    ):
        assert job_id in jobs
        assert jobs[job_id].enabled is False


def test_golden_dataset_has_three_cases_for_each_required_genus():
    path = Path(__file__).parents[1] / "app/features/ingestion/evaluation/dinosaur_retrieval_golden.jsonl"
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
    snapshot = session.exec(select(RagSourceSnapshot)).one()
    case = RetrievalCase(
        id="case", subject_name="Example", query="q",
        relevant_document_ids={"wiki:1:intro": 3},
        snapshot_hashes={"wikipedia": snapshot.source_hash},
    )
    prepared = prepare_retrieval_cases([case], session.exec(select(RagSourceSnapshot)).all())
    assert prepared[0].filters["subject_id"] == "dinosaur:7"
    with pytest.raises(ValueError, match="stale"):
        prepare_retrieval_cases(
            [case.model_copy(update={"snapshot_hashes": {"wikipedia": "changed"}})],
            session.exec(select(RagSourceSnapshot)).all(),
        )


def test_knowledge_runner_routes_scope_and_control_flags(monkeypatch):
    captured = {}

    class _Summary:
        def print_exit(self) -> int:
            return 0

    def fake_acquire(**kwargs):
        captured.update(
            {
                "dinos": [subject.name for subject in kwargs["subjects"]],
                "sources": kwargs["sources"],
                "max_items": kwargs["max_items"],
                "overwrite": kwargs["overwrite"],
                "dry_run": kwargs["dry_run"],
            }
        )
        return _Summary()

    monkeypatch.setattr(ingestion_runner, "acquire_knowledge", fake_acquire)
    monkeypatch.setattr(ingestion_runner, "require_openalex_credentials", lambda *a, **k: None)
    monkeypatch.setattr(ingestion_runner, "bound_wikipedia", lambda **k: object())
    monkeypatch.setattr(ingestion_runner, "bound_openalex", lambda **k: object())
    monkeypatch.setattr(
        ingestion_runner,
        "list_dinosaur_knowledge_subjects",
        lambda session, names=None: [SimpleNamespace(name=name) for name in (names or [])],
    )
    monkeypatch.setattr(
        ingestion_runner,
        "Session",
        lambda _engine: contextlib.nullcontext(SimpleNamespace()),
    )
    monkeypatch.setattr(ingestion_runner, "SqlSnapshotStore", lambda session, **kwargs: object())

    result = ingestion_runner._run_dinosaur_knowledge_acquire(
        {
            "dinos": ["Example"],
            "sources": "Wikipedia,OpenAlex",
            "max_items": "2",
            "overwrite": True,
            "dry_run": True,
        }
    )

    assert result == 0
    assert captured == {
        "dinos": ["Example"],
        "sources": ["wikipedia", "openalex"],
        "max_items": 2,
        "overwrite": True,
        "dry_run": True,
    }


def test_evaluation_runner_routes_dataset_mode_and_regression(monkeypatch):
    captured = {}

    def fake_evaluate(**kwargs):
        captured.update(
            {
                "dataset": str(kwargs["dataset_path"]),
                "retrieval_mode": kwargs["mode"],
                "output_report": kwargs["output_path"],
                "baseline_report": kwargs["baseline_path"],
                "maximum_regression": kwargs["maximum_regression"],
            }
        )
        return object(), None

    monkeypatch.setattr(ingestion_runner, "evaluate_knowledge", fake_evaluate)
    monkeypatch.setattr(ingestion_runner, "evaluation_exit", lambda *args: 0)
    monkeypatch.setattr(
        ingestion_runner,
        "Session",
        lambda _engine: contextlib.nullcontext(SimpleNamespace()),
    )
    monkeypatch.setattr(ingestion_runner, "SqlSnapshotStore", lambda session, **kwargs: object())

    result = ingestion_runner._run_dinosaur_knowledge_evaluate({
        "dataset": "cases.jsonl", "retrieval_mode": "hybrid",
        "output_report": "report.json", "baseline_report": "baseline.json",
        "maximum_regression": "0.01",
    })
    assert result == 0
    assert captured == {
        "dataset": "cases.jsonl", "retrieval_mode": "hybrid",
        "output_report": "report.json", "baseline_report": "baseline.json",
        "maximum_regression": 0.01,
    }
