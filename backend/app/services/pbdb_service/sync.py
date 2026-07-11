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
    unchanged: int = 0
    skipped: int = 0
    failed: int = 0


@dataclass
class SyncSummary:
    total_dinosaurs: int
    counters: SyncCounters = field(default_factory=SyncCounters)
    dry_run: bool = False
    overwrite: bool = False
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
    text = str(raw).strip().strip('"')
    if not text:
        return None
    return text[:max_len]


def _parse_optional_int(raw: Any) -> int | None:
    if raw is None or raw == "":
        return None
    try:
        return int(str(raw).strip())
    except (TypeError, ValueError):
        return None


def build_fossil_description(record: dict[str, Any]) -> str | None:
    """Compose a readable narrative from PBDB location and stratigraphy notes."""
    parts: list[str] = []

    geog = _parse_optional_str(record.get("geogcomments"), max_len=3000)
    if geog:
        parts.append(geog)

    strat = _parse_optional_str(record.get("stratcomments"), max_len=2000)
    if strat:
        parts.append(strat)

    lith = _parse_optional_str(record.get("lithdescript"), max_len=500)
    if lith:
        parts.append(f"Lithology: {lith}")

    if not parts:
        return None
    return " — ".join(parts)[:4000]


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
        early_interval=_parse_optional_str(record.get("early_interval"), max_len=100),
        family=_parse_optional_str(record.get("family"), max_len=100),
        collection_name=_parse_optional_str(record.get("collection_name"), max_len=255),
        collection_dates=_parse_optional_str(record.get("collection_dates"), max_len=100),
        stratcomments=_parse_optional_str(record.get("stratcomments"), max_len=4000),
        lithdescript=_parse_optional_str(record.get("lithdescript"), max_len=500),
        collectors=_parse_optional_str(record.get("collectors"), max_len=500),
        museum=_parse_optional_str(record.get("museum"), max_len=100),
        pres_mode=_parse_optional_str(record.get("pres_mode"), max_len=50),
        preservation_quality=_parse_optional_str(record.get("preservation_quality"), max_len=50),
        abund_value=_parse_optional_int(record.get("abund_value")),
        abund_unit=_parse_optional_str(record.get("abund_unit"), max_len=50),
        description=build_fossil_description(record),
    )


_FOSSIL_MUTABLE_FIELDS = (
    "dinosaur_id",
    "identified_name",
    "latitude",
    "longitude",
    "country_code",
    "state",
    "geological_formation",
    "min_age_ma",
    "max_age_ma",
    "early_interval",
    "family",
    "collection_name",
    "collection_dates",
    "stratcomments",
    "lithdescript",
    "collectors",
    "museum",
    "pres_mode",
    "preservation_quality",
    "abund_value",
    "abund_unit",
    "description",
)


def _copy_fossil_fields(source: Fossil, target: Fossil) -> None:
    for field_name in _FOSSIL_MUTABLE_FIELDS:
        setattr(target, field_name, getattr(source, field_name))


def _load_dinosaurs(session: Session, *, dinos: list[str] | None) -> list[Dinosaur]:
    stmt = select(Dinosaur).order_by(Dinosaur.name)
    if dinos:
        stmt = stmt.where(dino_name_match_clause(dinos))
    return list(session.exec(stmt).all())


def _get_existing(session: Session, occurrence_no: int) -> Fossil | None:
    return session.get(Fossil, occurrence_no)


def _apply_record(existing: Fossil | None, row: Fossil, *, overwrite: bool) -> str:
    if existing is None:
        return "fetch_new"
    if not overwrite:
        return "skip_existing"
    _copy_fossil_fields(row, existing)
    return "fetch_update"


def sync_fossils(
    session: Session,
    *,
    client: PbdbClient | None = None,
    dry_run: bool = False,
    overwrite: bool = False,
    dinos: list[str] | None = None,
) -> SyncSummary:
    """Fetch PBDB occurrences per catalog genus and upsert into fossil."""
    own_client = client is None
    pbdb = client or PbdbClient()
    start = time.monotonic()
    counters = SyncCounters()
    dinosaurs = _load_dinosaurs(session, dinos=dinos)
    total = len(dinosaurs)

    logger.info(
        "pbdb_fossil_sync: starting total_dinosaurs=%d overwrite=%s dry_run=%s dinos=%s",
        total,
        overwrite,
        dry_run,
        dinos,
    )

    try:
        for index, dinosaur in enumerate(dinosaurs, start=1):
            prefix = f"pbdb_fossil_sync: [{index}/{total}] {dinosaur.name}"
            genus_fetched = 0
            genus_updated = 0
            genus_unchanged = 0
            genus_skipped = 0
            try:
                logger.info("%s action=start", prefix)
                for record in pbdb.iter_occurrences(base_name=dinosaur.name):
                    row = _record_to_fossil(record, dinosaur_id=dinosaur.id)
                    if row is None:
                        counters.skipped += 1
                        genus_skipped += 1
                        continue

                    existing = _get_existing(session, row.id)
                    outcome = _apply_record(existing, row, overwrite=overwrite)

                    if outcome == "skip_existing":
                        counters.unchanged += 1
                        genus_unchanged += 1
                        continue

                    if dry_run:
                        if outcome == "fetch_new":
                            counters.fetched += 1
                            genus_fetched += 1
                        else:
                            counters.updated += 1
                            genus_updated += 1
                        continue

                    if outcome == "fetch_new":
                        session.add(row)
                        counters.fetched += 1
                        genus_fetched += 1
                    else:
                        session.add(existing)
                        counters.updated += 1
                        genus_updated += 1
                    session.commit()
                logger.info(
                    "%s action=done fetched=%d updated=%d unchanged=%d skipped=%d",
                    prefix,
                    genus_fetched,
                    genus_updated,
                    genus_unchanged,
                    genus_skipped,
                )
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
        overwrite=overwrite,
        elapsed_s=elapsed,
    )
    logger.info(
        "pbdb_fossil_sync: finished dinosaurs=%d fetched=%d updated=%d unchanged=%d "
        "skipped=%d failed=%d overwrite=%s dry_run=%s elapsed_s=%.1f",
        total,
        counters.fetched,
        counters.updated,
        counters.unchanged,
        counters.skipped,
        counters.failed,
        overwrite,
        dry_run,
        elapsed,
    )
    return summary


def sync_exit_code(summary: SyncSummary) -> int:
    """Return non-zero when any records failed."""
    if summary.counters.failed == 0:
        return 0
    return 1
