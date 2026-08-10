"""Human-readable checkpoint status tables."""

from __future__ import annotations

from datetime import datetime
from typing import Any

from mesozoica_ai.common.config import AiConfig
from mesozoica_ai.index import pipeline_fingerprint


def format_checkpoint_status(
    rows: list[Any],
    *,
    current_pipeline_fingerprint: str | None = None,
    subject_header: str = "SUBJECT",
) -> str:
    """Render acquisition/indexing status for duck-typed checkpoint rows."""
    header = (
        f"{subject_header:28} {'SOURCE':10} {'ACQUIRE':10} {'INDEX':10} "
        f"{'TRIES':7} {'CONTENT':8} {'PIPELINE':8} {'REINDEX REASON':18} "
        f"{'ACQUIRED AT':20} {'INDEXED AT':20} LAST ERROR"
    )
    lines = [header, "-" * len(header)]
    for row in rows:
        error = (row.index_error or row.acquisition_error or "").replace("\n", " ")[:80]
        reason = _reindex_reason(row, current_pipeline_fingerprint)
        lines.append(
            f"{str(row.subject_name)[:28]:28} {str(row.source)[:10]:10} "
            f"{str(row.acquisition_status)[:10]:10} {str(row.index_status)[:10]:10} "
            f"{row.acquisition_attempts}/{row.index_attempts:<5} "
            f"{_short(row.content_hash):8} "
            f"{_short(row.indexed_pipeline_fingerprint):8} "
            f"{reason[:18]:18} "
            f"{_timestamp(row.acquisition_finished_at):20} "
            f"{_timestamp(row.index_finished_at):20} {error}"
        )
    if not rows:
        lines.append("No knowledge snapshots found.")
    return "\n".join(lines)


def knowledge_status(
    store: Any,
    *,
    config: AiConfig | None = None,
    names: list[str] | None = None,
    subject_header: str = "SUBJECT",
) -> str:
    """Format status for every checkpoint in a SnapshotStore."""
    active = config or AiConfig()
    return format_checkpoint_status(
        store.list_all(names=names),
        current_pipeline_fingerprint=pipeline_fingerprint(config=active),
        subject_header=subject_header,
    )


def evaluation_exit(report: Any, comparison: Any | None = None) -> int:
    """Print evaluation JSON and return a regression-aware exit code."""
    print(report.model_dump_json(indent=2))
    if comparison is None:
        return 0
    print(comparison.model_dump_json(indent=2))
    return 0 if comparison.passed else 1


def _timestamp(value: datetime | None) -> str:
    return value.isoformat(timespec="seconds") if value is not None else "-"


def _short(value: str | None) -> str:
    return value[:8] if value else "-"


def _reindex_reason(row: Any, fingerprint: str | None) -> str:
    if row.acquisition_status != "succeeded":
        return "acquisition"
    if row.indexed_hash != row.content_hash:
        return "content changed"
    if fingerprint and row.indexed_pipeline_fingerprint != fingerprint:
        return "pipeline changed"
    if row.index_status != "succeeded":
        return row.index_status
    return "current"
