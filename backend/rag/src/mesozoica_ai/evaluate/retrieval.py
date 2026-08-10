"""Deterministic retrieval evaluation and regression comparison."""

from __future__ import annotations

import json
import logging
import math
from collections.abc import Callable, Iterable, Sequence
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from pydantic import BaseModel, Field, field_validator

logger = logging.getLogger(__name__)


class RetrievalCase(BaseModel):
    """A graded document-relevance judgment for one query."""

    id: str
    subject_name: str | None = None
    query: str
    relevant_document_ids: dict[str, int] = Field(min_length=1)
    filters: dict[str, Any] = Field(default_factory=dict)
    top_k: int = Field(default=8, ge=1)
    snapshot_hashes: dict[str, str] = Field(default_factory=dict)

    @field_validator("relevant_document_ids")
    @classmethod
    def validate_relevance_grades(cls, values: dict[str, int]) -> dict[str, int]:
        """Require nonblank document IDs and conventional positive grades 1 through 4."""
        if any(not identifier.strip() or not 1 <= grade <= 4 for identifier, grade in values.items()):
            raise ValueError("relevance judgments require document IDs and grades from 1 to 4")
        return values

    @field_validator("snapshot_hashes")
    @classmethod
    def validate_snapshot_hashes(cls, values: dict[str, str]) -> dict[str, str]:
        """Validate pinned source hashes when an application dataset provides them."""
        if any(
            not source.strip()
            or len(value) != 64
            or any(character not in "0123456789abcdef" for character in value.casefold())
            for source, value in values.items()
        ):
            raise ValueError("snapshot hashes must be 64-character SHA-256 hex values")
        return {source: value.casefold() for source, value in values.items()}


class RetrievalCaseResult(BaseModel):
    """Exact metrics and ranking returned for one case."""

    id: str
    precision_at_k: float
    recall_at_k: float
    hit_rate_at_k: float
    reciprocal_rank: float
    ndcg_at_k: float
    returned_document_ids: list[str]


class RetrievalExperiment(BaseModel):
    """Parameters required to reproduce a retrieval evaluation."""

    evaluated_at: datetime
    mode: str
    candidate_k: int
    fetch_k: int
    top_k: int
    pipeline_fingerprint: str
    case_count: int


class RetrievalEvaluationReport(BaseModel):
    """Macro-averaged metrics with reproducible experiment metadata."""

    experiment: RetrievalExperiment
    cases: list[RetrievalCaseResult]
    precision_at_k: float
    recall_at_k: float
    hit_rate_at_k: float
    mrr: float
    ndcg_at_k: float


class RegressionComparison(BaseModel):
    """Metric changes against a baseline and an acceptance decision."""

    maximum_regression: float
    regressions: dict[str, float]
    passed: bool


class RetrievalRun(BaseModel):
    """One retrieval configuration passed to an application-owned adapter."""

    mode: str = "semantic_hybrid"
    candidate_k: int = Field(default=50, ge=1)
    fetch_k: int = Field(default=24, ge=1)
    top_k: int = Field(default=8, ge=1)


def evaluate_retrieval(
    cases: Iterable[RetrievalCase],
    retrieve: Callable[[RetrievalCase, RetrievalRun], list[str]],
    *,
    mode: str = "semantic_hybrid",
    candidate_k: int = 50,
    fetch_k: int = 24,
    top_k: int = 8,
    pipeline_fingerprint: str,
) -> RetrievalEvaluationReport:
    """Compute precision, recall, hit-rate, MRR, and graded nDCG locally."""
    results: list[RetrievalCaseResult] = []
    for case in cases:
        case_k = min(case.top_k, top_k)
        run = RetrievalRun(
            mode=mode,
            top_k=case_k,
            fetch_k=max(fetch_k, case_k),
            candidate_k=max(candidate_k, fetch_k, case_k),
        )
        returned = list(dict.fromkeys(retrieve(case, run)))[:case_k]
        relevant = set(case.relevant_document_ids)
        hits = [document_id for document_id in returned if document_id in relevant]
        first_rank = next(
            (rank for rank, identifier in enumerate(returned, 1) if identifier in relevant), None
        )
        dcg = sum(
            (2 ** case.relevant_document_ids.get(identifier, 0) - 1) / math.log2(rank + 1)
            for rank, identifier in enumerate(returned, 1)
        )
        ideal_labels = sorted(case.relevant_document_ids.values(), reverse=True)[:case_k]
        ideal_dcg = sum(
            (2**label - 1) / math.log2(rank + 1)
            for rank, label in enumerate(ideal_labels, 1)
        )
        results.append(RetrievalCaseResult(
            id=case.id,
            precision_at_k=len(hits) / case_k,
            recall_at_k=len(set(hits)) / len(relevant),
            hit_rate_at_k=float(bool(hits)),
            reciprocal_rank=1 / first_rank if first_rank else 0,
            ndcg_at_k=dcg / ideal_dcg if ideal_dcg else 0,
            returned_document_ids=returned,
        ))
    if not results:
        raise ValueError("At least one retrieval case is required")
    count = len(results)
    report = RetrievalEvaluationReport(
        experiment=RetrievalExperiment(
            evaluated_at=datetime.now(timezone.utc), mode=mode, candidate_k=candidate_k,
            fetch_k=fetch_k, top_k=top_k, pipeline_fingerprint=pipeline_fingerprint,
            case_count=count,
        ),
        cases=results,
        precision_at_k=sum(item.precision_at_k for item in results) / count,
        recall_at_k=sum(item.recall_at_k for item in results) / count,
        hit_rate_at_k=sum(item.hit_rate_at_k for item in results) / count,
        mrr=sum(item.reciprocal_rank for item in results) / count,
        ndcg_at_k=sum(item.ndcg_at_k for item in results) / count,
    )
    logger.info("rag.evaluate", extra={"rag": {
        "case_count": count, "mode": mode,
        "pipeline_fingerprint": pipeline_fingerprint,
        "precision_at_k": report.precision_at_k, "recall_at_k": report.recall_at_k,
        "mrr": report.mrr, "ndcg_at_k": report.ndcg_at_k,
    }})
    return report


def compare_to_baseline(
    current: RetrievalEvaluationReport,
    baseline: RetrievalEvaluationReport,
    *,
    maximum_regression: float = 0.02,
) -> RegressionComparison:
    """Fail when any aggregate metric loses more than the allowed absolute amount."""
    if not 0 <= maximum_regression <= 1:
        raise ValueError("maximum_regression must be between 0 and 1")
    if {case.id for case in current.cases} != {case.id for case in baseline.cases}:
        raise ValueError("baseline and current reports must contain the same case IDs")
    if current.experiment.top_k != baseline.experiment.top_k:
        raise ValueError("baseline and current reports must use the same top_k")
    names = ("precision_at_k", "recall_at_k", "hit_rate_at_k", "mrr", "ndcg_at_k")
    regressions = {
        name: getattr(baseline, name) - getattr(current, name) for name in names
    }
    return RegressionComparison(
        maximum_regression=maximum_regression,
        regressions=regressions,
        passed=all(change <= maximum_regression for change in regressions.values()),
    )


def load_retrieval_cases(path: str | Path) -> list[RetrievalCase]:
    """Load Pydantic cases from JSONL."""
    with Path(path).open(encoding="utf-8") as handle:
        return [RetrievalCase.model_validate(json.loads(line)) for line in handle if line.strip()]


def load_evaluation_report(path: str | Path) -> RetrievalEvaluationReport:
    """Load a prior report for baseline comparison."""
    return RetrievalEvaluationReport.model_validate_json(Path(path).read_text(encoding="utf-8"))


def prepare_retrieval_cases(
    cases: list[RetrievalCase],
    snapshots: Sequence[Any],
    *,
    namespace: str = "mesozoica",
    subject_kind: str = "dinosaur",
) -> list[RetrievalCase]:
    """Bind golden cases to current snapshot hashes and subject filters."""
    actual = {
        (row.subject_name.casefold(), row.source): row.source_hash for row in snapshots
    }
    subject_ids = {row.subject_name.casefold(): row.subject_id for row in snapshots}
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
        case.model_copy(
            update={
                "filters": {
                    **case.filters,
                    "namespace": namespace,
                    "subject_id": f"{subject_kind}:{subject_ids[case.subject_name.casefold()]}",
                }
            }
        )
        for case in cases
    ]
