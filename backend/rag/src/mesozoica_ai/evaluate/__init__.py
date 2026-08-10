"""Offline retrieval metrics. Foundry stays as evaluate.foundry."""

from .live import evaluate_against_index, evaluate_knowledge
from .retrieval import (
    RegressionComparison,
    RetrievalCase,
    RetrievalCaseResult,
    RetrievalEvaluationReport,
    RetrievalExperiment,
    RetrievalRun,
    compare_to_baseline,
    evaluate_retrieval,
    load_evaluation_report,
    load_retrieval_cases,
    prepare_retrieval_cases,
)
from .status import evaluation_exit, format_checkpoint_status, knowledge_status

__all__ = [
    "RegressionComparison",
    "RetrievalCase",
    "RetrievalCaseResult",
    "RetrievalEvaluationReport",
    "RetrievalExperiment",
    "RetrievalRun",
    "compare_to_baseline",
    "evaluate_against_index",
    "evaluate_knowledge",
    "evaluate_retrieval",
    "evaluation_exit",
    "format_checkpoint_status",
    "knowledge_status",
    "load_evaluation_report",
    "load_retrieval_cases",
    "prepare_retrieval_cases",
]
