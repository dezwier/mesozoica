"""Answer a user question from indexed dinosaur knowledge (evidence only).

Pipeline:
  1. optional dinosaur scope (--dinos)
  2. retrieve most relevant Azure chunks for the question
  3. assemble one prompt with evidence only (no application context)
  4. validate structured answer + citations

Requires knowledge already acquired (01), embedded (02), and ingested (03).

  cd backend
  .venv/bin/python rag/scripts/05_answer_question.py \\
      --question "What did Abrosaurus eat?"
  .venv/bin/python rag/scripts/05_answer_question.py \\
      --question "Where was Abrosaurus found?" --dinos Abrosaurus --show-chunks
  .venv/bin/python rag/scripts/05_answer_question.py \\
      --question "Classify Abrosaurus" --dinos Abrosaurus --chunks-only
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
from pathlib import Path

_BACKEND_ROOT = Path(__file__).resolve().parents[2]
if str(_BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(_BACKEND_ROOT))

from dotenv import load_dotenv

load_dotenv(_BACKEND_ROOT / ".env")
load_dotenv(_BACKEND_ROOT / "rag" / ".env")

logging.basicConfig(
    level=logging.INFO,
    format="%(levelname)s %(name)s: %(message)s",
)
for _noisy in (
    "azure",
    "azure.core.pipeline.policies.http_logging_policy",
    "httpx",
    "httpcore",
    "openai",
):
    logging.getLogger(_noisy).setLevel(logging.WARNING)

logger = logging.getLogger("answer")

from sqlmodel import Session

from app.core.database import engine
from app.features.ingestion.public import parse_dino_names
from app.features.specimens.public import list_dinosaur_knowledge_subjects
from mesozoica_ai.common import AiConfig
from mesozoica_ai.common.batch import DEFAULT_NAMESPACE
from mesozoica_ai.common.models import RetrievalMode
from mesozoica_ai.generate import (
    GroundedAnswer,
    log_retrieved_chunks,
    prompt_rag,
    require_one_subject,
    retrieved_chunk_record,
)
from mesozoica_ai.index import embed_query, retrieve_chunks
from mesozoica_ai.index.runtime import build_store

ANSWER_INSTRUCTIONS = (
    "Answer the question using only the supplied evidence. "
    "Be concise and accurate. Cite every chunk that supports the answer."
)


def run(
    *,
    question: str,
    dinos: list[str] | None = None,
    show_chunks: bool = False,
    chunks_only: bool = False,
    mode: str | None = None,
) -> int:
    if not question.strip():
        raise ValueError("--question must not be blank")
    if show_chunks and chunks_only:
        raise ValueError("Use only one of --show-chunks or --chunks-only")
    if dinos is not None and len(dinos) != 1:
        raise ValueError("Pass at most one dinosaur with --dinos")

    config = AiConfig()
    retrieval_mode = RetrievalMode(mode) if mode else None
    query = question.strip()
    filters: dict[str, str] = {"namespace": DEFAULT_NAMESPACE}
    subject_info: dict[str, object] | None = None

    if dinos:
        with Session(engine) as session:
            subjects = list_dinosaur_knowledge_subjects(session, names=dinos)
            subject = require_one_subject(subjects, requested=dinos[0])
        filters["subject_id"] = f"dinosaur:{subject.id}"
        subject_info = {"id": subject.id, "name": subject.name}
        logger.info("subject: %s (id=%s)", subject.name, subject.id)
        indexed = build_store(config, write_enabled=False).list_ids(filters)
        if not indexed:
            raise RuntimeError(
                f"No Azure chunks for {subject.name} ({filters['subject_id']}). "
                "Run acquire, embed, then ingest first:\n"
                f"  .venv/bin/python rag/scripts/01_acquire_dinosaur_knowledge.py "
                f"--dinos {subject.name}\n"
                f"  .venv/bin/python rag/scripts/02_embed_dinosaur_knowledge.py "
                f"--dinos {subject.name}\n"
                f"  .venv/bin/python rag/scripts/03_ingest_dinosaur_knowledge.py "
                f"--dinos {subject.name}"
            )

    active_mode = retrieval_mode or RetrievalMode(config.retrieval_mode)
    logger.info(
        "retrieve: mode=%s query=%r filters=%s",
        active_mode.value,
        query,
        filters,
    )
    logger.info("application_context: none")

    chunks = retrieve_chunks(
        query,
        query_embedding=embed_query(query, config=config),
        filters=filters,
        mode=retrieval_mode,
        config=config,
    )
    chunk_records = [retrieved_chunk_record(chunk) for chunk in chunks]
    log_retrieved_chunks(logger, chunk_records)

    base_payload = {
        "question": query,
        "filters": filters,
        "mode": active_mode.value,
        "subject": subject_info,
        "chunks": chunk_records,
    }

    if chunks_only:
        print(json.dumps(base_payload, indent=2, ensure_ascii=False, default=str))
        return 0

    logger.info("prompt → validate …")
    answer = prompt_rag(
        GroundedAnswer,
        query=query,
        evidence=chunks,
        application_context=None,
        instructions=ANSWER_INSTRUCTIONS,
        config=config,
    )
    logger.info("validated: citations=%s", len(answer.source_chunk_ids))
    if show_chunks:
        payload = {**base_payload, "answer": answer.model_dump(mode="json")}
        print(json.dumps(payload, indent=2, ensure_ascii=False, default=str))
    else:
        print(answer.model_dump_json(indent=2))
    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--question", required=True, help="User question to answer")
    parser.add_argument(
        "--dinos",
        nargs="+",
        default=None,
        help="Optional exactly-one dinosaur scope for retrieval filters",
    )
    parser.add_argument(
        "--mode",
        choices=("keyword", "vector", "hybrid", "semantic_hybrid"),
        default=None,
        help="Retrieval mode (default: RAG_RETRIEVAL_MODE / hybrid)",
    )
    parser.add_argument(
        "--show-chunks",
        action="store_true",
        help="Include retrieved chunks (with metadata) in the JSON output",
    )
    parser.add_argument(
        "--chunks-only",
        action="store_true",
        help="Retrieve and print chunks with metadata; skip answer generation",
    )
    args = parser.parse_args()
    try:
        raise SystemExit(
            run(
                question=args.question,
                dinos=parse_dino_names(args.dinos) if args.dinos else None,
                show_chunks=args.show_chunks,
                chunks_only=args.chunks_only,
                mode=args.mode,
            )
        )
    except Exception as exc:
        logger.error("%s", exc)
        raise SystemExit(1) from exc
