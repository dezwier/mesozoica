from __future__ import annotations

from datetime import datetime

from sqlmodel import Session, col, select

from app.features.ingestion.models.rag_source_snapshot import RagSourceSnapshot


def format_knowledge_status(
    session: Session, *, dinosaur_names: list[str] | None = None,
    current_pipeline_fingerprint: str | None = None,
) -> str:
    rows = list(
        session.exec(
            select(RagSourceSnapshot)
            .where(RagSourceSnapshot.subject_kind == "dinosaur")
            .order_by(col(RagSourceSnapshot.subject_name), col(RagSourceSnapshot.source))
        ).all()
    )
    if dinosaur_names:
        names = {name.strip().casefold() for name in dinosaur_names if name.strip()}
        rows = [row for row in rows if row.subject_name.casefold() in names]
    header = (
        f"{'DINOSAUR':28} {'SOURCE':10} {'ACQUIRE':10} {'INDEX':10} "
        f"{'TRIES':7} {'CONTENT':8} {'PIPELINE':8} {'REINDEX REASON':18} "
        f"{'ACQUIRED AT':20} {'INDEXED AT':20} LAST ERROR"
    )
    lines = [header, "-" * len(header)]
    for row in rows:
        error = (row.index_error or row.acquisition_error or "").replace("\n", " ")[:80]
        reason = _reindex_reason(row, current_pipeline_fingerprint)
        lines.append(
            f"{row.subject_name[:28]:28} {row.source[:10]:10} "
            f"{row.acquisition_status[:10]:10} {row.index_status[:10]:10} "
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


def _timestamp(value: datetime | None) -> str:
    return value.isoformat(timespec="seconds") if value is not None else "-"


def _short(value: str | None) -> str:
    return value[:8] if value else "-"


def _reindex_reason(row: RagSourceSnapshot, fingerprint: str | None) -> str:
    if row.acquisition_status != "succeeded":
        return "acquisition"
    if row.indexed_hash != row.content_hash:
        return "content changed"
    if fingerprint and row.indexed_pipeline_fingerprint != fingerprint:
        return "pipeline changed"
    if row.index_status != "succeeded":
        return row.index_status
    return "current"
