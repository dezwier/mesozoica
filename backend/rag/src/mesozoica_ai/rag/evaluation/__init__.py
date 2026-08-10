"""Offline retrieval metrics and optional Foundry cloud judges."""

from .foundry import FoundryEvaluationResult, FoundryRagEvaluator, RagEvaluationRecord
from .retrieval import (
    RegressionComparison, RetrievalCase, RetrievalCaseResult, RetrievalEvaluationReport,
    RetrievalRun,
    RetrievalExperiment, compare_to_baseline, evaluate_retrieval, load_evaluation_report,
    load_retrieval_cases,
)

__all__ = [
    "FoundryEvaluationResult", "FoundryRagEvaluator", "RagEvaluationRecord",
    "RegressionComparison", "RetrievalCase", "RetrievalCaseResult",
    "RetrievalEvaluationReport", "RetrievalExperiment", "RetrievalRun",
    "compare_to_baseline",
    "evaluate_retrieval", "load_evaluation_report", "load_retrieval_cases",
]
