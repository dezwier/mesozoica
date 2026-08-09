from __future__ import annotations

import json
import math
from collections.abc import Callable, Iterable
from pathlib import Path

from pydantic import BaseModel, Field

from mesozoica_ai.knowledge.models import RetrievalRequest, RetrievedChunk


class RetrievalCase(BaseModel):
    id: str
    query: str
    relevant_document_ids: dict[str, int] = Field(min_length=1)
    filters: dict = Field(default_factory=dict)
    top_k: int = Field(default=8, ge=1)


class RetrievalCaseResult(BaseModel):
    id: str
    precision_at_k: float
    recall_at_k: float
    hit_rate_at_k: float
    reciprocal_rank: float
    ndcg_at_k: float
    returned_document_ids: list[str]


class RetrievalEvaluationReport(BaseModel):
    cases: list[RetrievalCaseResult]
    precision_at_k: float
    recall_at_k: float
    hit_rate_at_k: float
    mrr: float
    ndcg_at_k: float


def evaluate_retrieval(
    cases: Iterable[RetrievalCase],
    retrieve: Callable[[RetrievalRequest], list[RetrievedChunk]],
) -> RetrievalEvaluationReport:
    results: list[RetrievalCaseResult] = []
    for case in cases:
        chunks = retrieve(
            RetrievalRequest(
                query=case.query,
                filters=case.filters,
                top_k=case.top_k,
                candidate_k=max(50, case.top_k),
            )
        )
        returned = list(dict.fromkeys(chunk.document_id for chunk in chunks))[: case.top_k]
        relevant = set(case.relevant_document_ids)
        hits = [document_id for document_id in returned if document_id in relevant]
        precision = len(hits) / case.top_k
        recall = len(set(hits)) / len(relevant)
        first_rank = next(
            (index for index, identifier in enumerate(returned, 1) if identifier in relevant),
            None,
        )
        dcg = sum(
            (2 ** case.relevant_document_ids.get(identifier, 0) - 1) / math.log2(rank + 1)
            for rank, identifier in enumerate(returned, 1)
        )
        ideal_labels = sorted(case.relevant_document_ids.values(), reverse=True)[: case.top_k]
        ideal_dcg = sum(
            (2**label - 1) / math.log2(rank + 1)
            for rank, label in enumerate(ideal_labels, 1)
        )
        results.append(
            RetrievalCaseResult(
                id=case.id,
                precision_at_k=precision,
                recall_at_k=recall,
                hit_rate_at_k=float(bool(hits)),
                reciprocal_rank=1 / first_rank if first_rank else 0.0,
                ndcg_at_k=dcg / ideal_dcg if ideal_dcg else 0.0,
                returned_document_ids=returned,
            )
        )
    if not results:
        raise ValueError("At least one retrieval case is required")
    count = len(results)
    return RetrievalEvaluationReport(
        cases=results,
        precision_at_k=sum(item.precision_at_k for item in results) / count,
        recall_at_k=sum(item.recall_at_k for item in results) / count,
        hit_rate_at_k=sum(item.hit_rate_at_k for item in results) / count,
        mrr=sum(item.reciprocal_rank for item in results) / count,
        ndcg_at_k=sum(item.ndcg_at_k for item in results) / count,
    )


def load_retrieval_cases(path: str | Path) -> list[RetrievalCase]:
    with Path(path).open(encoding="utf-8") as handle:
        return [RetrievalCase.model_validate(json.loads(line)) for line in handle if line.strip()]
