"""Application-owned dinosaur retrieval evaluation and stale-label safeguards."""

from __future__ import annotations

from pathlib import Path

from sqlmodel import Session, select

from app.features.ingestion.models.rag_source_snapshot import (
    RAG_STATUS_SUCCEEDED,
    RagSourceSnapshot,
)
from mesozoica_ai.knowledge import (
    KnowledgeBase,
    RetrievalMode,
    RetrievalRequest,
)
from mesozoica_ai.rag.evaluation import (
    RegressionComparison,
    RetrievalCase,
    RetrievalEvaluationReport,
    compare_to_baseline,
    evaluate_retrieval,
    load_evaluation_report,
    load_retrieval_cases,
)


def evaluate_dinosaur_knowledge(
    session: Session,
    *,
    knowledge: KnowledgeBase,
    dataset_path: str | Path,
    mode: RetrievalMode = RetrievalMode.SEMANTIC_HYBRID,
    output_path: str | Path | None = None,
    baseline_path: str | Path | None = None,
    maximum_regression: float = 0.02,
) -> tuple[RetrievalEvaluationReport, RegressionComparison | None]:
    """Evaluate current snapshots, refusing unlabeled or stale source judgments."""
    cases = load_retrieval_cases(dataset_path)
    cases = _validate_and_prepare_cases(session, cases)

    def retrieve_document_ids(case, run) -> list[str]:
        result = knowledge.retrieve(RetrievalRequest(
            query=case.query,
            filters=case.filters,
            mode=RetrievalMode(run.mode),
            candidate_k=run.candidate_k,
            fetch_k=run.fetch_k,
            top_k=run.top_k,
        ))
        return [chunk.document_id for chunk in result.chunks]

    report = evaluate_retrieval(
        cases,
        retrieve_document_ids,
        mode=mode.value,
        candidate_k=50,
        fetch_k=24,
        top_k=8,
        pipeline_fingerprint=knowledge.pipeline_fingerprint,
    )
    comparison = None
    if baseline_path:
        comparison = compare_to_baseline(
            report,
            load_evaluation_report(baseline_path),
            maximum_regression=maximum_regression,
        )
    if output_path:
        Path(output_path).write_text(report.model_dump_json(indent=2), encoding="utf-8")
    return report, comparison


def _validate_and_prepare_cases(
    session: Session, cases: list[RetrievalCase]
) -> list[RetrievalCase]:
    rows = session.exec(
        select(RagSourceSnapshot).where(
            RagSourceSnapshot.subject_kind == "dinosaur",
            RagSourceSnapshot.acquisition_status == RAG_STATUS_SUCCEEDED,
        )
    ).all()
    actual = {
        (row.subject_name.casefold(), row.source): row.source_hash for row in rows
    }
    subject_ids = {row.subject_name.casefold(): row.subject_id for row in rows}
    stale: list[str] = []
    for case in cases:
        subject = str(case.subject_name or "").casefold()
        if not subject or not case.snapshot_hashes:
            stale.append(f"{case.id} (missing labeling hashes)")
            continue
        for source, expected in case.snapshot_hashes.items():
            if actual.get((subject, source)) != expected:
                stale.append(f"{case.id}/{source}")
    if stale:
        raise ValueError(
            "Golden cases are unlabeled or stale against current source snapshots; "
            "deliberately review and relabel: " + ", ".join(stale)
        )
    return [
        case.model_copy(update={"filters": {
            **case.filters,
            "namespace": "mesozoica",
            "subject_id": f"dinosaur:{subject_ids[case.subject_name.casefold()]}",
        }})
        for case in cases
    ]
