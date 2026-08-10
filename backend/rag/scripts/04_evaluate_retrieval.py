"""Evaluate retrieval with evaluate_against_index against a golden set."""

from __future__ import annotations

import argparse

from mesozoica_ai import AiConfig
from mesozoica_ai.common.models import RetrievalMode
from mesozoica_ai.evaluate import evaluate_against_index, load_retrieval_cases


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("dataset")
    parser.add_argument(
        "--mode",
        choices=[item.value for item in RetrievalMode],
        default="semantic_hybrid",
    )
    parser.add_argument("--baseline")
    args = parser.parse_args(argv)

    report, comparison = evaluate_against_index(
        load_retrieval_cases(args.dataset),
        config=AiConfig(),
        mode=args.mode,
        baseline_path=args.baseline,
    )
    print(report.model_dump_json(indent=2))
    if comparison is not None:
        print(comparison.model_dump_json(indent=2))
        return 0 if comparison.passed else 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
