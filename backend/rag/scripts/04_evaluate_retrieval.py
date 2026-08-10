"""Evaluate retrieval against the golden JSONL dataset."""

from pathlib import Path

from mesozoica_ai import AiConfig
from mesozoica_ai.evaluate import evaluate_against_index, load_retrieval_cases

DATASET = Path(__file__).resolve().parents[1] / "evaluation" / "dinosaur_retrieval_golden.jsonl"

report, comparison = evaluate_against_index(
    load_retrieval_cases(DATASET),
    config=AiConfig(),
    mode="semantic_hybrid",
)
print(report.model_dump_json(indent=2))
if comparison is not None:
    print(comparison.model_dump_json(indent=2))
