"""Orchestrate PBDB fossil occurrence sync into the database."""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from decimal import Decimal, InvalidOperation
from typing import Any

from sqlmodel import Session, select

from app.models.dinosaur import Dinosaur
from app.models.fossil import Fossil
from app.services.dinosaur_name_filter import dino_name_match_clause
from app.services.pbdb_service.client import PbdbClient

logger = logging.getLogger("pbdb_fossil_sync")


@dataclass
class SyncCounters:
    fetched: int = 0
    updated: int = 0
    skipped: int = 0
    failed: int = 0


@dataclass
class SyncSummary:
    total_dinosaurs: int
    counters: SyncCounters = field(default_factory=SyncCounters)
    dry_run: bool = False
    elapsed_s: float = 0.0

    @property
    def failure_rate(self) -> float:
        attempted = self.counters.fetched + self.counters.updated + self.counters.failed
        if attempted == 0:
            return 0.0
        return self.counters.failed / attempted


def _parse_occurrence_no(raw: Any) -> int | None:
    if raw is None:
        return None
    try:
        return int(str(raw).strip())
    except (TypeError, ValueError):
        return None


def _parse_decimal(raw: Any, *, precision: int, scale: int) -> Decimal | None:
    if raw is None or raw == "":
        return None
    try:
        value = Decimal(str(raw))
    except (InvalidOperation, ValueError, TypeError):
        return None
    quant = Decimal(10) ** -scale
    max_digits = precision - scale
    try:
        return value.quantize(quant)
    except InvalidOperation:
        return None


def _parse_optional_str(raw: Any, *, max_len: int) -> str | None:
    if raw is None:
        return None
    text = str(raw).strip()
    if not text:
        return None
    return text[:max_len]


def _is_bird_record(record: dict[str, Any]) -> bool:
    primary = str(record.get("primary_name") or "").strip()
    accepted = str(record.get("accepted_name") or "").strip()
    return primary == "Aves" or accepted == "Aves"


def _record_to_fossil(record: dict[str, Any], *, dinosaur_id: int) -> Fossil | None:
    occurrence_no = _parse_occurrence_no(record.get("occurrence_no"))
    if occurrence_no is None:
        return None
    if _is_bird_record(record):
        return None

    return Fossil(
        id=occurrence_no,
        dinosaur_id=dinosaur_id,
        identified_name=_parse_optional_str(record.get("identified_name"), max_len=255),
        latitude=_parse_decimal(record.get("lat"), precision=9, scale=6),
        longitude=_parse_decimal(record.get("lng"), precision=9, scale=6),
        country_code=_parse_optional_str(record.get("cc"), max_len=2),
        state=_parse_optional_str(record.get("state"), max_len=100),
        geological_formation=_parse_optional_str(record.get("formation"), max_len=255),
        min_age_ma=_parse_decimal(record.get("min_ma"), precision=5, scale=2),
        max_age_ma=_parse_decimal(record.get("max_ma"), precision=5, scale=2),
    )


def _load_dinosaurs(session: Session, *, dinos: list[str] | None) -> list[Dinosaur]:
    stmt = select(Dinosaur).order_by(Dinosaur.name)
    if dinos:
        stmt = stmt.where(dino_name_match_clause(dinos))
    return list(session.exec(stmt).all())


def _get_existing(session: Session, occurrence_no: int) -> Fossil | None:
    return session.get(Fossil, occurrence_no)


def _apply_record(existing: Fossil | None, row: Fossil) -> str:
    if existing is None:
        return "fetch_new"
    existing.dinosaur_id = row.dinosaur_id
    existing.identified_name = row.identified_name
    existing.latitude = row.latitude
    existing.longitude = row.longitude
    existing.country_code = row.country_code
    existing.state = row.state
    existing.geological_formation = row.geological_formation
    existing.min_age_ma = row.min_age_ma
    existing.max_age_ma = row.max_age_ma
    return "fetch_update"


def sync_fossils(
    session: Session,
    *,
    client: PbdbClient | None = None,
    dry_run: bool = False,
    dinos: list[str] | None = None,
) -> SyncSummary:
    """Fetch PBDB occurrences per catalog genus and upsert into fossil."""
    own_client = client is None
    pbdb = client or PbdbClient()
    start = time.monotonic()
    counters = SyncCounters()
    dinosaurs = _load_dinosaurs(session, dinos=dinos)
    total = len(dinosaurs)

    try:
        for index, dinosaur in enumerate(dinosaurs, start=1):
            prefix = f"pbdb_fossil_sync: [{index}/{total}] {dinosaur.name}"
            try:
                for record in pbdb.iter_occurrences(base_name=dinosaur.name):
                    row = _record_to_fossil(record, dinosaur_id=dinosaur.id)
                    if row is None:
                        counters.skipped += 1
                        continue

                    existing = _get_existing(session, row.id)
                    outcome = _apply_record(existing, row)

                    if dry_run:
                        if outcome == "fetch_new":
                            counters.fetched += 1
                        else:
                            counters.updated += 1
                        continue

                    if outcome == "fetch_new":
                        session.add(row)
                        counters.fetched += 1
                    else:
                        session.add(existing)
                        counters.updated += 1
                    session.commit()
            except Exception as exc:
                counters.failed += 1
                logger.error("%s action=failed error=%s", prefix, exc)
                session.rollback()
    finally:
        if own_client:
            pbdb.close()

    elapsed = time.monotonic() - start
    summary = SyncSummary(
        total_dinosaurs=total,
        counters=counters,
        dry_run=dry_run,
        elapsed_s=elapsed,
    )
    logger.info(
        "pbdb_fossil_sync: finished dinosaurs=%d fetched=%d updated=%d skipped=%d failed=%d "
        "dry_run=%s elapsed_s=%.1f",
        total,
        counters.fetched,
        counters.updated,
        counters.skipped,
        counters.failed,
        dry_run,
        elapsed,
    )
    return summary


def sync_exit_code(summary: SyncSummary) -> int:
    """Return non-zero when any records failed."""
    if summary.counters.failed == 0:
        return 0
    return 1
