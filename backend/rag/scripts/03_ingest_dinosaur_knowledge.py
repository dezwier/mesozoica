"""Ingest SQL-cached embeddings from dinosaur_knowledge_chunk into Azure Search.

Requires sources that already succeeded embedding (02_embed_dinosaur_knowledge.py).
Does not call the embedding API.

  cd backend
  .venv/bin/python rag/scripts/03_ingest_dinosaur_knowledge.py
  .venv/bin/python rag/scripts/03_ingest_dinosaur_knowledge.py --dinos Tyrannosaurus
  .venv/bin/python rag/scripts/03_ingest_dinosaur_knowledge.py --recreate-index
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

logger = logging.getLogger("ingest")

from sqlmodel import Session

from app.core.database import engine
from app.features.ingestion.application.dinosaur_knowledge.repository import (
    dinosaur_knowledge_repo,
)
from app.features.ingestion.public import parse_dino_names
from mesozoica_ai.common import AiConfig, sql_embedded_overview
from mesozoica_ai.common.inventory import overview_drift_lines
from mesozoica_ai.index import azure_knowledge_overview, ingest_knowledge


def run(
    *,
    dry_run: bool = False,
    overwrite: bool = False,
    recreate_index: bool = False,
    dinos: list[str] | None = None,
    sources: list[str] | None = None,
    max_items: int | None = None,
) -> int:
    sources = sources or ["wikipedia", "openalex"]
    logger.info(
        "Ingest dinosaur_knowledge → Azure (name_filter=%s sources=%s "
        "dry_run=%s overwrite=%s recreate=%s)",
        ",".join(dinos) if dinos else "(none)",
        ",".join(sources),
        dry_run,
        overwrite,
        recreate_index,
    )
    with Session(engine) as session:
        repo = dinosaur_knowledge_repo(session)
        summary = ingest_knowledge(
            repo=repo,
            names=dinos,
            sources=sources,
            max_items=max_items,
            overwrite=overwrite,
            dry_run=dry_run,
            recreate_index=recreate_index,
        )
        embedded = sql_embedded_overview(repo)
        logger.info(
            "Done: succeeded=%s skipped=%s failed=%s",
            summary.succeeded,
            summary.skipped,
            summary.failed,
        )
        for line in embedded.log_lines(title="Embedded (SQL chunks)"):
            logger.info("%s", line)
        if not dry_run:
            try:
                import time

                time.sleep(2)
                azure_overview = azure_knowledge_overview(
                    config=AiConfig(),
                    repo=repo,
                )
                for line in azure_overview.log_lines(title="In Azure Search"):
                    logger.info("%s", line)
                for line in overview_drift_lines(
                    embedded,
                    azure_overview,
                    left_name="Embedded",
                    right_name="Azure",
                ):
                    logger.info("%s", line)
            except Exception as exc:
                logger.warning("Azure overview unavailable (%s)", exc)
    print(json.dumps(summary.model_dump(), indent=2, default=str))
    return summary.exit_code


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dinos",
        nargs="+",
        default=None,
        help="Optional name filter on dinosaur_knowledge rows (not the full catalog)",
    )
    parser.add_argument(
        "--sources", nargs="+", choices=("wikipedia", "openalex"), default=None
    )
    parser.add_argument("--max-items", type=int, default=None)
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument(
        "--recreate-index",
        action="store_true",
        help="Wipe Azure index and re-ingest every embedded dinosaur_knowledge row",
    )
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    raise SystemExit(
        run(
            dry_run=args.dry_run,
            overwrite=args.overwrite,
            recreate_index=args.recreate_index,
            dinos=parse_dino_names(args.dinos) if args.dinos else None,
            sources=args.sources,
            max_items=args.max_items,
        )
    )
