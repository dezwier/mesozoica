"""Live-index evaluation helpers."""

from __future__ import annotations

from pathlib import Path
from typing import Any, Sequence

from mesozoica_ai.common.config import AiConfig
from mesozoica_ai.common.models import RetrievalMode
from mesozoica_ai.evaluate.retrieval import (
    compare_to_baseline,
    evaluate_retrieval,
    load_evaluation_report,
    load_retrieval_cases,
    prepare_retrieval_cases,
)
from mesozoica_ai.index import embed_query, pipeline_fingerprint, retrieve_chunks


def evaluate_against_index(
    cases: Sequence[Any],
    *,
    config: AiConfig,
    mode: str = "semantic_hybrid",
    candidate_k: int = 50,
    fetch_k: int = 24,
    top_k: int = 8,
    baseline_path: str | None = None,
    output_path: str | None = None,
    maximum_regression: float = 0.02,
) -> tuple[Any, Any]:
    """Run offline metrics against the live Azure index; optionally compare a baseline."""
    retrieval_mode = mode if isinstance(mode, str) else getattr(mode, "value", str(mode))

    def retrieve_document_ids(case: Any, run: Any) -> list[str]:
        active = RetrievalMode(run.mode)
        query_vector = (
            None
            if active is RetrievalMode.KEYWORD
            else embed_query(case.query, config=config)
        )
        result = retrieve_chunks(
            case.query,
            query_embedding=query_vector,
            filters=case.filters,
            mode=active,
            candidate_k=run.candidate_k,
            fetch_k=run.fetch_k,
            top_k=run.top_k,
            include_diagnostics=True,
            config=config,
        )
        return [chunk.document_id for chunk in result.chunks]

    report = evaluate_retrieval(
        cases,
        retrieve_document_ids,
        mode=retrieval_mode,
        candidate_k=candidate_k,
        fetch_k=fetch_k,
        top_k=top_k,
        pipeline_fingerprint=pipeline_fingerprint(config=config),
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


def evaluate_knowledge(
    *,
    repo: Any,
    dataset_path: str | Any,
    config: AiConfig | None = None,
    mode: str = "semantic_hybrid",
    output_path: str | None = None,
    baseline_path: str | None = None,
    maximum_regression: float = 0.02,
) -> tuple[Any, Any]:
    """Prepare golden cases against stored hashes, then evaluate the live index."""
    from mesozoica_ai.index import list_knowledge_rows

    active = config or AiConfig()
    retrieval_mode = mode if isinstance(mode, str) else getattr(mode, "value", str(mode))
    cases = prepare_retrieval_cases(
        load_retrieval_cases(dataset_path),
        list_knowledge_rows(repo, succeeded_only=True),
    )
    return evaluate_against_index(
        cases,
        config=active,
        mode=retrieval_mode,
        baseline_path=baseline_path,
        output_path=output_path,
        maximum_regression=maximum_regression,
    )
