"""Orchestrate PBDB fossil occurrence sync into the database."""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from decimal import Decimal, InvalidOperation
from typing import Any

from sqlalchemy import case
from sqlmodel import Session, col, func, select

from app.models.dinosaur import Dinosaur
from app.models.fossil import Fossil
from app.services.dinosaur_image_service.sync import CURATED_MEDIA_PATH
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
    since: datetime | None = None
    stale_skipped: int = 0
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
        identified_rank=_parse_optional_str(record.get("identified_rank"), max_len=50),
        accepted_name=_parse_optional_str(record.get("accepted_name"), max_len=255),
        accepted_no=_parse_optional_int(record.get("accepted_no")),
        accepted_rank=_parse_optional_str(record.get("accepted_rank"), max_len=50),
        accepted_attr=_parse_optional_str(record.get("accepted_attr"), max_len=255),
        genus=_parse_optional_str(record.get("genus"), max_len=100),
        family=_parse_optional_str(record.get("family"), max_len=100),
        taxon_order=_parse_optional_str(record.get("order"), max_len=100),
        taxon_class=_parse_optional_str(record.get("class"), max_len=100),
        phylum=_parse_optional_str(record.get("phylum"), max_len=100),
        latitude=_parse_decimal(record.get("lat"), precision=9, scale=6),
        longitude=_parse_decimal(record.get("lng"), precision=9, scale=6),
        country_code=_parse_optional_str(record.get("cc"), max_len=2),
        state=_parse_optional_str(record.get("state"), max_len=100),
        geogcomments=_parse_optional_str(record.get("geogcomments"), max_len=4000),
        geogscale=_parse_optional_str(record.get("geogscale"), max_len=100),
        geoplate=_parse_optional_int(record.get("geoplate")),
        latlng_basis=_parse_optional_str(record.get("latlng_basis"), max_len=100),
        latlng_precision=_parse_optional_int(record.get("latlng_precision")),
        paleolat=_parse_decimal(record.get("paleolat"), precision=9, scale=6),
        paleolng=_parse_decimal(record.get("paleolng"), precision=9, scale=6),
        paleomodel=_parse_optional_str(record.get("paleomodel"), max_len=50),
        paleoage=_parse_optional_str(record.get("paleoage"), max_len=50),
        geological_formation=_parse_optional_str(record.get("formation"), max_len=255),
        min_age_ma=_parse_decimal(record.get("min_ma"), precision=5, scale=2),
        max_age_ma=_parse_decimal(record.get("max_ma"), precision=5, scale=2),
        early_interval=_parse_optional_str(record.get("early_interval"), max_len=100),
        stratcomments=_parse_optional_str(record.get("stratcomments"), max_len=4000),
        stratscale=_parse_optional_str(record.get("stratscale"), max_len=100),
        lithdescript=_parse_optional_str(record.get("lithdescript"), max_len=500),
        lithology1=_parse_optional_str(record.get("lithology1"), max_len=100),
        lithadj1=_parse_optional_str(record.get("lithadj1"), max_len=100),
        concentration=_parse_optional_str(record.get("concentration"), max_len=100),
        temporal_resolution=_parse_optional_str(record.get("temporal_resolution"), max_len=100),
        collection_name=_parse_optional_str(record.get("collection_name"), max_len=255),
        collection_aka=_parse_optional_str(record.get("collection_aka"), max_len=255),
        collection_no=_parse_optional_int(record.get("collection_no")),
        collection_dates=_parse_optional_str(record.get("collection_dates"), max_len=100),
        collection_type=_parse_optional_str(record.get("collection_type"), max_len=50),
        collection_methods=_parse_optional_str(record.get("collection_methods"), max_len=2000),
        collectors=_parse_optional_str(record.get("collectors"), max_len=500),
        museum=_parse_optional_str(record.get("museum"), max_len=100),
        research_group=_parse_optional_str(record.get("research_group"), max_len=100),
        occurrence_comments=_parse_optional_str(record.get("occurrence_comments"), max_len=4000),
        composition=_parse_optional_str(record.get("composition"), max_len=100),
        architecture=_parse_optional_str(record.get("architecture"), max_len=100),
        fragmentation=_parse_optional_str(record.get("fragmentation"), max_len=100),
        pres_mode=_parse_optional_str(record.get("pres_mode"), max_len=100),
        preservation_quality=_parse_optional_str(record.get("preservation_quality"), max_len=50),
        abund_value=_parse_optional_int(record.get("abund_value")),
        abund_unit=_parse_optional_str(record.get("abund_unit"), max_len=50),
        fossilsfrom1=_parse_optional_str(record.get("fossilsfrom1"), max_len=10),
        size_classes=_parse_optional_str(record.get("size_classes"), max_len=100),
        record_type=_parse_optional_str(record.get("record_type"), max_len=20),
        diet=_parse_optional_str(record.get("diet"), max_len=100),
        environment=_parse_optional_str(record.get("environment"), max_len=255),
        taxon_environment=_parse_optional_str(record.get("taxon_environment"), max_len=100),
        life_habit=_parse_optional_str(record.get("life_habit"), max_len=255),
        motility=_parse_optional_str(record.get("motility"), max_len=100),
        reproduction=_parse_optional_str(record.get("reproduction"), max_len=255),
        ontogeny=_parse_optional_str(record.get("ontogeny"), max_len=255),
        reference_no=_parse_optional_int(record.get("reference_no")),
        ref_author=_parse_optional_str(record.get("ref_author"), max_len=255),
        ref_pubyr=_parse_optional_int(record.get("ref_pubyr")),
        reid_no=_parse_optional_int(record.get("reid_no")),
        description=None,
    )


_FOSSIL_MUTABLE_FIELDS = (
    "dinosaur_id",
    "identified_name",
    "identified_rank",
    "accepted_name",
    "accepted_no",
    "accepted_rank",
    "accepted_attr",
    "genus",
    "family",
    "taxon_order",
    "taxon_class",
    "phylum",
    "latitude",
    "longitude",
    "country_code",
    "state",
    "geogcomments",
    "geogscale",
    "geoplate",
    "latlng_basis",
    "latlng_precision",
    "paleolat",
    "paleolng",
    "paleomodel",
    "paleoage",
    "geological_formation",
    "min_age_ma",
    "max_age_ma",
    "early_interval",
    "stratcomments",
    "stratscale",
    "lithdescript",
    "lithology1",
    "lithadj1",
    "concentration",
    "temporal_resolution",
    "collection_name",
    "collection_aka",
    "collection_no",
    "collection_dates",
    "collection_type",
    "collection_methods",
    "collectors",
    "museum",
    "research_group",
    "occurrence_comments",
    "composition",
    "architecture",
    "fragmentation",
    "pres_mode",
    "preservation_quality",
    "abund_value",
    "abund_unit",
    "fossilsfrom1",
    "size_classes",
    "record_type",
    "diet",
    "environment",
    "taxon_environment",
    "life_habit",
    "motility",
    "reproduction",
    "ontogeny",
    "reference_no",
    "ref_author",
    "ref_pubyr",
    "reid_no",
    "description",
)


def _copy_fossil_fields(source: Fossil, target: Fossil) -> None:
    for field_name in _FOSSIL_MUTABLE_FIELDS:
        setattr(target, field_name, getattr(source, field_name))


def resolve_since(
    *,
    since: datetime | None = None,
    stale_days: int | None = None,
) -> datetime | None:
    """Return cutoff for fossils_insert_time filtering (exclusive upper bound)."""
    if since is not None:
        return since
    if stale_days is not None:
        return datetime.now(timezone.utc) - timedelta(days=stale_days)
    return None


def _count_dinosaurs(session: Session, *, dinos: list[str] | None) -> int:
    stmt = select(func.count()).select_from(Dinosaur)
    if dinos:
        stmt = stmt.where(dino_name_match_clause(dinos))
    return int(session.exec(stmt).one())


def _load_dinosaurs(
    session: Session,
    *,
    dinos: list[str] | None,
    since: datetime | None,
    overwrite: bool,
) -> list[Dinosaur]:
    stmt = select(Dinosaur)
    if dinos:
        stmt = stmt.where(dino_name_match_clause(dinos))
    if since is not None and not overwrite:
        stmt = stmt.where(
            col(Dinosaur.fossils_insert_time).is_(None)
            | (col(Dinosaur.fossils_insert_time) < since)
        )
    custom_image_priority = case(
        (
            col(Dinosaur.main_image_url).is_not(None)
            & col(Dinosaur.main_image_url).contains(CURATED_MEDIA_PATH),
            0,
        ),
        else_=1,
    )
    stmt = stmt.order_by(custom_image_priority, Dinosaur.name)
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
    since: datetime | None = None,
    stale_days: int | None = None,
) -> SyncSummary:
    """Fetch PBDB occurrences per catalog genus and upsert into fossil."""
    own_client = client is None
    pbdb = client or PbdbClient()
    start = time.monotonic()
    counters = SyncCounters()
    cutoff = resolve_since(since=since, stale_days=stale_days)
    total_matching = _count_dinosaurs(session, dinos=dinos)
    dinosaurs = _load_dinosaurs(session, dinos=dinos, since=cutoff, overwrite=overwrite)
    stale_skipped = total_matching - len(dinosaurs) if cutoff is not None and not overwrite else 0
    total = len(dinosaurs)

    logger.info(
        "pbdb_fossil_sync: starting total_dinosaurs=%d stale_skipped=%d overwrite=%s "
        "dry_run=%s since=%s dinos=%s",
        total,
        stale_skipped,
        overwrite,
        dry_run,
        cutoff.isoformat() if cutoff else None,
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
                if not dry_run:
                    dinosaur.fossils_insert_time = datetime.now(timezone.utc)
                    session.add(dinosaur)
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
        overwrite=overwrite,
        since=cutoff,
        stale_skipped=stale_skipped,
        elapsed_s=elapsed,
    )
    logger.info(
        "pbdb_fossil_sync: finished dinosaurs=%d stale_skipped=%d fetched=%d updated=%d "
        "unchanged=%d skipped=%d failed=%d overwrite=%s dry_run=%s since=%s elapsed_s=%.1f",
        total,
        stale_skipped,
        counters.fetched,
        counters.updated,
        counters.unchanged,
        counters.skipped,
        counters.failed,
        overwrite,
        dry_run,
        cutoff.isoformat() if cutoff else None,
        elapsed,
    )
    return summary


def sync_exit_code(summary: SyncSummary) -> int:
    """Return non-zero when any records failed."""
    if summary.counters.failed == 0:
        return 0
    return 1
