"""Generate one cited multiple-choice quiz from indexed dinosaur knowledge.

Pipeline:
  1. resolve dinosaur subject
  2. retrieve most relevant Azure chunks (optional: print with clear metadata)
  3. load application context (placeholder: user level / language / difficulty)
  4. assemble one prompt and validate structured output + citations

Requires the subject to already be acquired (01), embedded (02), and ingested (03).

  cd backend
  .venv/bin/python rag/scripts/04_generate_quiz.py --dinos Abrosaurus
  .venv/bin/python rag/scripts/04_generate_quiz.py --dinos Abrosaurus --show-chunks
  .venv/bin/python rag/scripts/04_generate_quiz.py --dinos Abrosaurus --chunks-only
  .venv/bin/python rag/scripts/04_generate_quiz.py --dinos Tyrannosaurus --difficulty hard
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
from pathlib import Path
from typing import Literal

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

logger = logging.getLogger("quiz")

from sqlmodel import Session

from app.core.database import engine
from app.features.ingestion.public import parse_dino_names
from app.features.specimens.public import list_dinosaur_knowledge_subjects
from mesozoica_ai.common import AiConfig
from mesozoica_ai.common.models import RetrievalMode
from mesozoica_ai.generate import (
    QuizQuestion,
    QuizUserContext,
    log_retrieved_chunks,
    prompt_rag,
    quiz_retrieval_plan,
    require_one_subject,
    retrieved_chunk_record,
)
from mesozoica_ai.index import embed_query, retrieve_chunks


def run(
    *,
    dinos: list[str],
    language: str = "English",
    level: str = "intermediate",
    difficulty: Literal["easy", "medium", "hard"] = "medium",
    show_chunks: bool = False,
    chunks_only: bool = False,
    mode: str | None = None,
) -> int:
    if len(dinos) != 1:
        raise ValueError("Pass exactly one dinosaur with --dinos")
    if show_chunks and chunks_only:
        raise ValueError("Use only one of --show-chunks or --chunks-only")

    user_context = QuizUserContext(
        language=language,
        knowledge_level=level,
        preferred_difficulty=difficulty,
    )
    config = AiConfig()
    retrieval_mode = RetrievalMode(mode) if mode else None

    with Session(engine) as session:
        subjects = list_dinosaur_knowledge_subjects(session, names=dinos)
        subject = require_one_subject(subjects, requested=dinos[0])

    query, filters, instructions = quiz_retrieval_plan(
        subject_id=subject.id,
        subject_name=subject.name,
        user_context=user_context,
    )
    logger.info("subject: %s (id=%s)", subject.name, subject.id)
    logger.info(
        "application_context (placeholder): language=%s level=%s difficulty=%s",
        user_context.language,
        user_context.knowledge_level,
        user_context.preferred_difficulty,
    )
    active_mode = retrieval_mode or RetrievalMode(config.retrieval_mode)
    logger.info(
        "retrieve: mode=%s query=%r filters=%s",
        active_mode.value,
        query,
        filters,
    )

    chunks = retrieve_chunks(
        query,
        query_embedding=embed_query(query, config=config),
        filters=filters,
        mode=retrieval_mode,
        config=config,
    )
    chunk_records = [retrieved_chunk_record(chunk) for chunk in chunks]
    log_retrieved_chunks(logger, chunk_records)

    if chunks_only:
        payload = {
            "subject": {"id": subject.id, "name": subject.name},
            "query": query,
            "filters": filters,
            "mode": active_mode.value,
            "application_context": user_context.model_dump(mode="json"),
            "chunks": chunk_records,
        }
        print(json.dumps(payload, indent=2, ensure_ascii=False, default=str))
        return 0

    logger.info("prompt → validate …")
    quiz = prompt_rag(
        QuizQuestion,
        query=query,
        evidence=chunks,
        application_context=user_context,
        instructions=instructions,
        config=config,
    )
    logger.info(
        "validated: topic=%s difficulty=%s options=%s citations=%s",
        quiz.topic,
        quiz.difficulty,
        len(quiz.options),
        len(quiz.source_chunk_ids),
    )
    if show_chunks:
        payload = {
            "subject": {"id": subject.id, "name": subject.name},
            "query": query,
            "filters": filters,
            "mode": active_mode.value,
            "application_context": user_context.model_dump(mode="json"),
            "chunks": chunk_records,
            "quiz": quiz.model_dump(mode="json"),
        }
        print(json.dumps(payload, indent=2, ensure_ascii=False, default=str))
    else:
        print(quiz.model_dump_json(indent=2))
    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dinos",
        nargs="+",
        required=True,
        help="Exactly one dinosaur name (must be indexed in Azure)",
    )
    parser.add_argument("--language", default="English")
    parser.add_argument(
        "--level",
        default="intermediate",
        help="Placeholder user knowledge level for application context",
    )
    parser.add_argument(
        "--difficulty",
        choices=("easy", "medium", "hard"),
        default="medium",
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
        help="Retrieve and print chunks with metadata; skip quiz generation",
    )
    args = parser.parse_args()
    try:
        raise SystemExit(
            run(
                dinos=parse_dino_names(args.dinos),
                language=args.language,
                level=args.level,
                difficulty=args.difficulty,
                show_chunks=args.show_chunks,
                chunks_only=args.chunks_only,
                mode=args.mode,
            )
        )
    except Exception as exc:
        logger.error("%s", exc)
        raise SystemExit(1) from exc
