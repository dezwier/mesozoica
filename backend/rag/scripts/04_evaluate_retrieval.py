"""Evaluate indexed retrieval cases and optionally compare a baseline."""

from __future__ import annotations

import argparse

from mesozoica_ai.knowledge import (
    KnowledgeBaseSettings,
    RetrievalMode,
    RetrievalRequest,
    create_knowledge_base,
)
from mesozoica_ai.rag.evaluation import (
    compare_to_baseline,
    evaluate_retrieval,
    load_evaluation_report,
    load_retrieval_cases,
)


def main(argv: list[str] | None = None) -> int:
    """Run local deterministic metrics; this example intentionally has no DB staleness check."""
    parser = argparse.ArgumentParser()
    parser.add_argument("dataset")
    parser.add_argument("--mode", choices=[item.value for item in RetrievalMode], default="semantic_hybrid")
    parser.add_argument("--baseline")
    args = parser.parse_args(argv)
    knowledge = create_knowledge_base(KnowledgeBaseSettings(), write_enabled=False)

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
        load_retrieval_cases(args.dataset),
        retrieve_document_ids,
        mode=args.mode,
        pipeline_fingerprint=knowledge.pipeline_fingerprint,
    )
    print(report.model_dump_json(indent=2))
    if args.baseline:
        comparison = compare_to_baseline(report, load_evaluation_report(args.baseline))
        print(comparison.model_dump_json(indent=2))
        return 0 if comparison.passed else 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
