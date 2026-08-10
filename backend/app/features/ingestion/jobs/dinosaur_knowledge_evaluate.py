"""Run the application-owned golden retrieval evaluation without generation writes."""

from __future__ import annotations

from pathlib import Path

from sqlmodel import Session

from app.core.database import engine
from app.features.ingestion.application.knowledge.evaluation import evaluate_dinosaur_knowledge
from mesozoica_ai.knowledge import (
    KnowledgeBaseSettings,
    RetrievalMode,
    create_knowledge_base,
)

DEFAULT_DATASET = Path(__file__).parents[1] / "evaluation" / "dinosaur_retrieval_golden.jsonl"


def run_evaluate_job(
    *,
    dataset: str | None = None,
    retrieval_mode: str = "semantic_hybrid",
    output_report: str | None = None,
    baseline_report: str | None = None,
    maximum_regression: float = 0.02,
) -> int:
    """Run local metrics and return nonzero when a configured baseline regresses."""
    knowledge = create_knowledge_base(KnowledgeBaseSettings(), write_enabled=False)
    with Session(engine) as session:
        report, comparison = evaluate_dinosaur_knowledge(
            session,
            knowledge=knowledge,
            dataset_path=dataset or DEFAULT_DATASET,
            mode=RetrievalMode(retrieval_mode),
            output_path=output_report,
            baseline_path=baseline_report,
            maximum_regression=maximum_regression,
        )
    print(report.model_dump_json(indent=2))
    if comparison:
        print(comparison.model_dump_json(indent=2))
    return 0 if comparison is None or comparison.passed else 1
