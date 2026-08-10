from types import SimpleNamespace
from pathlib import Path

import pytest
from sqlmodel import select

from app.crons.config import load_cron_config
from app.features.ingestion import runner as ingestion_runner
from app.features.ingestion.application.knowledge import (
    QuizQuestion,
    acquire_dinosaur_knowledge,
    format_knowledge_status,
    index_dinosaur_knowledge,
)
from app.features.ingestion.application.knowledge.evaluation import _validate_and_prepare_cases
from app.features.ingestion.models.rag_source_snapshot import (
    RAG_STATUS_FAILED,
    RAG_STATUS_PENDING,
    RAG_STATUS_SUCCEEDED,
    RagSourceSnapshot,
)
from app.features.specimens.public import DinosaurKnowledgeSubject
from mesozoica_ai.rag.evaluation import RetrievalCase, load_retrieval_cases
from mesozoica_ai.sources import SourceDocument


SUBJECT = DinosaurKnowledgeSubject(id=7, name="Example", wikipedia_title="Example")


class FakeWikipedia:
    def __init__(self, text="Wikipedia text"):
        self.text = text
        self.calls = 0

    def fetch(self, title):
        self.calls += 1
        return [
            SourceDocument(
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
    def search(self, query, *, limit=10):
        raise RuntimeError("OpenAlex unavailable")


class FakeOpenAlex:
    def search(self, query, *, limit=10):
        return [
            SourceDocument(
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


def test_acquisition_persists_independent_source_states_and_resumes(session):
    wiki = FakeWikipedia()
    summary = acquire_dinosaur_knowledge(
        session,
        subjects=[SUBJECT],
        wikipedia=wiki,
        openalex=FailingOpenAlex(),
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
        wikipedia=wiki,
        openalex=FailingOpenAlex(),
        sources=["wikipedia"],
    )
    assert resumed.skipped == 1
    assert wiki.calls == 1


def test_changed_overwrite_marks_snapshot_for_reindex(session):
    first = FakeWikipedia("old")
    acquire_dinosaur_knowledge(
        session,
        subjects=[SUBJECT],
        wikipedia=first,
        openalex=None,
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
        wikipedia=FakeWikipedia("new"),
        openalex=None,
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
        wikipedia=FakeWikipedia("same"),
        openalex=None,
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
        wikipedia=FakeWikipedia("same"),
        openalex=None,
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
        wikipedia=FakeWikipedia(),
        openalex=None,
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
        wikipedia=provider,
        openalex=None,
        sources=["wikipedia"],
    )

    assert summary.succeeded == 1
    assert provider.calls == 1


def test_acquisition_dry_run_does_not_create_checkpoints(session):
    summary = acquire_dinosaur_knowledge(
        session,
        subjects=[SUBJECT],
        wikipedia=None,
        openalex=None,
        dry_run=True,
    )

    assert summary.candidates == 2
    assert summary.skipped == 2
    assert list(session.exec(select(RagSourceSnapshot)).all()) == []


class FakeIndex:
    def __init__(self):
        self.ensured = 0
        self.recreated = 0

    def ensure(self):
        self.ensured += 1

    def recreate(self):
        self.recreated += 1


class FakeKnowledge:
    def __init__(self):
        self.calls = []
        self.pipeline_fingerprint = "pipeline-v2"

    def sync(self, documents, *, scope):
        self.calls.append((documents, scope))


def test_indexing_uses_source_scope_and_recreate_resets_checkpoints(session):
    acquire_dinosaur_knowledge(
        session,
        subjects=[SUBJECT],
        wikipedia=FakeWikipedia(),
        openalex=None,
        sources=["wikipedia"],
    )
    knowledge = FakeKnowledge()
    index = FakeIndex()
    summary = index_dinosaur_knowledge(
        session,
        knowledge=knowledge,
        index=index,
        recreate_index=True,
    )
    snapshot = session.exec(select(RagSourceSnapshot)).one()

    assert summary.succeeded == 1
    assert index.recreated == 1
    assert snapshot.index_status == RAG_STATUS_SUCCEEDED
    assert snapshot.indexed_hash == snapshot.content_hash
    assert snapshot.indexed_pipeline_fingerprint == "pipeline-v2"
    assert knowledge.calls[0][1] == {
        "namespace": "mesozoica",
        "subject_id": "dinosaur:7",
        "source": "wikipedia",
    }


def test_recreate_index_rejects_partial_scope(session):
    with pytest.raises(ValueError, match="unscoped"):
        index_dinosaur_knowledge(
            session, knowledge=FakeKnowledge(), index=FakeIndex(),
            dinosaur_names=["Example"], recreate_index=True,
        )


def test_indexing_continues_after_one_source_fails(session):
    acquire_dinosaur_knowledge(
        session,
        subjects=[SUBJECT],
        wikipedia=FakeWikipedia(),
        openalex=FakeOpenAlex(),
    )

    class OneFailureKnowledge(FakeKnowledge):
        def sync(self, documents, *, scope):
            super().sync(documents, scope=scope)
            if scope["source"] == "openalex":
                raise RuntimeError("embedding unavailable")

    summary = index_dinosaur_knowledge(
        session,
        knowledge=OneFailureKnowledge(),
        index=FakeIndex(),
    )
    rows = list(session.exec(select(RagSourceSnapshot)).all())
    by_source = {row.source: row for row in rows}

    assert summary.failed == 1
    assert summary.succeeded == 1
    assert by_source["openalex"].index_status == RAG_STATUS_FAILED
    assert by_source["wikipedia"].index_status == RAG_STATUS_SUCCEEDED


def test_pipeline_change_reindexes_unchanged_content(session):
    acquire_dinosaur_knowledge(
        session, subjects=[SUBJECT], wikipedia=FakeWikipedia(), openalex=None,
        sources=["wikipedia"],
    )
    first = FakeKnowledge()
    index_dinosaur_knowledge(session, knowledge=first, index=FakeIndex(), sources=["wikipedia"])
    second = FakeKnowledge()
    second.pipeline_fingerprint = "pipeline-v3"
    summary = index_dinosaur_knowledge(
        session, knowledge=second, index=FakeIndex(), sources=["wikipedia"]
    )
    snapshot = session.exec(select(RagSourceSnapshot)).one()
    assert summary.succeeded == 1
    assert len(second.calls) == 1
    assert snapshot.indexed_pipeline_fingerprint == "pipeline-v3"


def test_status_output_and_quiz_validation(session):
    acquire_dinosaur_knowledge(
        session,
        subjects=[SUBJECT],
        wikipedia=FakeWikipedia(),
        openalex=None,
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
        session, subjects=[SUBJECT], wikipedia=FakeWikipedia(), openalex=None,
        sources=["wikipedia"],
    )
    snapshot = session.exec(select(RagSourceSnapshot)).one()
    case = RetrievalCase(
        id="case", subject_name="Example", query="q",
        relevant_document_ids={"wiki:1:intro": 3},
        snapshot_hashes={"wikipedia": snapshot.source_hash},
    )
    prepared = _validate_and_prepare_cases(session, [case])
    assert prepared[0].filters["subject_id"] == "dinosaur:7"
    with pytest.raises(ValueError, match="stale"):
        _validate_and_prepare_cases(
            session, [case.model_copy(update={"snapshot_hashes": {"wikipedia": "changed"}})]
        )


def test_knowledge_runner_routes_scope_and_control_flags(monkeypatch):
    captured = {}

    def fake_run(**kwargs):
        captured.update(kwargs)
        return 0

    monkeypatch.setattr(
        ingestion_runner.dinosaur_knowledge_acquire, "run_acquire_job", fake_run
    )
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
    monkeypatch.setattr(
        ingestion_runner.dinosaur_knowledge_evaluate,
        "run_evaluate_job",
        lambda **kwargs: captured.update(kwargs) or 0,
    )
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
