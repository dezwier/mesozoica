"""Orchestrate fossil clean table rebuild from raw fossil data."""

from __future__ import annotations

import logging
import time
from collections import defaultdict
from dataclasses import dataclass, field

from sqlalchemy import delete
from sqlmodel import Session, col, select

from app.models.dinosaur import Dinosaur
from app.models.fossil import Fossil
from app.models.fossil_clean import FossilClean
from app.models.site_clean import SiteClean
from app.models.site_type import SiteType
from app.services.dinosaur_name_filter import dino_name_match_clause
from app.services.fossil_clean_service.rules import (
    ages_for_site,
    fossil_comment,
    fossil_name,
    fossil_type,
    formation_for_site,
    infer_preservation_quality,
    parse_collection_years,
    period_for_ages,
    rock_type_for_site,
    sub_category,
)
from app.services.site_service.site_type_fallback import (
    load_site_types_by_period,
    period_to_type_ids,
    pick_site_type_id_for_period,
)

logger = logging.getLogger("fossil_clean_sync")


@dataclass
class SyncCounters:
    sites_written: int = 0
    site_types_written: int = 0
    fossils_written: int = 0
    fossils_skipped: int = 0
    with_sub_category: int = 0
    with_collection_years: int = 0
    with_preservation_quality: int = 0


@dataclass
class SyncSummary:
    total_source_fossils: int
    counters: SyncCounters = field(default_factory=SyncCounters)
    dry_run: bool = False
    partial: bool = False
    elapsed_s: float = 0.0


@dataclass
class _SiteDraft:
    site: SiteClean
    period: str | None


def _fossil_query(session: Session, *, dinos: list[str] | None):
    stmt = select(Fossil)
    if dinos:
        stmt = stmt.join(Dinosaur, col(Fossil.dinosaur_id) == col(Dinosaur.id)).where(
            dino_name_match_clause(dinos)
        )
    return stmt


def _site_members(session: Session, collection_nos: set[int]) -> dict[int, list[Fossil]]:
    if not collection_nos:
        return {}
    stmt = select(Fossil).where(col(Fossil.collection_no).in_(collection_nos))
    grouped: dict[int, list[Fossil]] = defaultdict(list)
    for fossil in session.exec(stmt).all():
        if fossil.collection_no is not None:
            grouped[fossil.collection_no].append(fossil)
    return grouped


def _build_site_draft(site_id: int, fossils_at_site: list[Fossil]) -> _SiteDraft | None:
    if not fossils_at_site:
        return None
    ref = fossils_at_site[0]
    min_age_ma, max_age_ma = ages_for_site(fossils_at_site)
    return _SiteDraft(
        site=SiteClean(
            site_id=site_id,
            latitude=ref.latitude,
            longitude=ref.longitude,
            country_code=ref.country_code,
            state=ref.state,
            rock_type=rock_type_for_site(fossils_at_site),
            formation=formation_for_site(fossils_at_site),
            min_age_ma=min_age_ma,
            max_age_ma=max_age_ma,
        ),
        period=period_for_ages(min_age_ma, max_age_ma),
    )


def _site_type_pairs(drafts: list[_SiteDraft]) -> set[tuple[str, str]]:
    pairs: set[tuple[str, str]] = set()
    for draft in drafts:
        if draft.period and draft.site.rock_type:
            pairs.add((draft.period, draft.site.rock_type))
    return pairs


def _write_site_types(
    session: Session,
    pairs: set[tuple[str, str]],
    *,
    full_refresh: bool,
) -> dict[tuple[str, str], int]:
    if full_refresh:
        session.exec(delete(SiteType))
        session.flush()

    mapping: dict[tuple[str, str], int] = {}
    for period, rock_type in sorted(pairs):
        if full_refresh:
            row = SiteType(period=period, rock_type=rock_type)
            session.add(row)
            session.flush()
            if row.id is None:
                session.refresh(row)
            mapping[(period, rock_type)] = row.id
            continue

        stmt = select(SiteType).where(
            SiteType.period == period,
            SiteType.rock_type == rock_type,
        )
        row = session.exec(stmt).first()
        if row is None:
            row = SiteType(period=period, rock_type=rock_type)
            session.add(row)
            session.flush()
            if row.id is None:
                session.refresh(row)
        mapping[(period, rock_type)] = row.id

    return mapping


def _finalize_site_rows(
    drafts: list[_SiteDraft],
    site_type_ids: dict[tuple[str, str], int],
    period_to_ids: dict[str, list[int]],
) -> list[SiteClean]:
    rows: list[SiteClean] = []
    for draft in drafts:
        if draft.period and draft.site.rock_type:
            draft.site.site_type_id = site_type_ids.get((draft.period, draft.site.rock_type))
        elif draft.period and not (draft.site.rock_type or "").strip():
            draft.site.site_type_id = pick_site_type_id_for_period(
                site_id=draft.site.site_id,
                period=draft.period,
                period_to_type_ids=period_to_ids,
            )
        else:
            draft.site.site_type_id = None
        rows.append(draft.site)
    return rows


def _build_fossil_clean(fossil: Fossil) -> FossilClean | None:
    if fossil.collection_no is None:
        return None
    kind = fossil_type(fossil.pres_mode)
    year_min, year_max = parse_collection_years(fossil.collection_dates)
    return FossilClean(
        fossil_id=fossil.id,
        site_id=fossil.collection_no,
        dinosaur_id=fossil.dinosaur_id,
        name=fossil_name(
            identified_name=fossil.identified_name,
            accepted_name=fossil.accepted_name,
            genus=fossil.genus,
        ),
        type=kind,
        sub_category=sub_category(
            fossil_kind=kind,
            common_body_parts=fossil.common_body_parts,
            rare_body_parts=fossil.rare_body_parts,
            associated_parts=fossil.associated_parts,
            feed_pred_traces=fossil.feed_pred_traces,
            occurrence_comments=fossil.occurrence_comments,
            component_comments=fossil.component_comments,
            pres_mode=fossil.pres_mode,
            articulated_parts=fossil.articulated_parts,
        ),
        preservation_quality=infer_preservation_quality(
            preservation_quality=fossil.preservation_quality,
            fragmentation=fossil.fragmentation,
            architecture=fossil.architecture,
        ),
        min_age_ma=fossil.min_age_ma,
        max_age_ma=fossil.max_age_ma,
        collection_year_min=year_min,
        collection_year_max=year_max,
        comment=fossil_comment(fossil),
    )


def _count_derived_fields(rows: list[FossilClean], counters: SyncCounters) -> None:
    for row in rows:
        if row.sub_category:
            counters.with_sub_category += 1
        if row.collection_year_min is not None:
            counters.with_collection_years += 1
        if row.preservation_quality:
            counters.with_preservation_quality += 1


def sync_clean_tables(
    session: Session,
    *,
    dry_run: bool = False,
    dinos: list[str] | None = None,
) -> SyncSummary:
    """Rebuild ``site_clean`` and ``fossil_clean`` from the raw ``fossil`` table."""
    started = time.monotonic()
    source_fossils = list(session.exec(_fossil_query(session, dinos=dinos)).all())
    counters = SyncCounters()

    fossil_rows: list[FossilClean] = []
    for fossil in source_fossils:
        row = _build_fossil_clean(fossil)
        if row is None:
            counters.fossils_skipped += 1
            continue
        fossil_rows.append(row)

    collection_nos = {fossil.collection_no for fossil in source_fossils if fossil.collection_no is not None}
    site_members = _site_members(session, collection_nos)
    site_drafts = [
        draft
        for site_id, members in sorted(site_members.items())
        if (draft := _build_site_draft(site_id, members)) is not None
    ]
    site_type_pairs = _site_type_pairs(site_drafts)
    site_rows = _finalize_site_rows(site_drafts, {})

    counters.fossils_written = len(fossil_rows)
    counters.sites_written = len(site_rows)
    counters.site_types_written = len(site_type_pairs)
    _count_derived_fields(fossil_rows, counters)

    summary = SyncSummary(
        total_source_fossils=len(source_fossils),
        counters=counters,
        dry_run=dry_run,
        partial=bool(dinos),
        elapsed_s=time.monotonic() - started,
    )

    logger.info(
        "%s action=summary source_fossils=%d site_types=%d sites=%d fossils=%d skipped=%d "
        "sub_category=%d collection_years=%d preservation_quality=%d dry_run=%s partial=%s",
        "fossil_clean_sync",
        summary.total_source_fossils,
        counters.site_types_written,
        counters.sites_written,
        counters.fossils_written,
        counters.fossils_skipped,
        counters.with_sub_category,
        counters.with_collection_years,
        counters.with_preservation_quality,
        dry_run,
        summary.partial,
    )

    if dry_run:
        return summary

    site_ids = {row.site_id for row in site_rows}
    missing_site_ids = {row.site_id for row in fossil_rows} - site_ids
    if missing_site_ids:
        sample = sorted(missing_site_ids)[:10]
        raise RuntimeError(
            f"fossil_clean references {len(missing_site_ids)} site_id(s) missing from site_clean; "
            f"sample={sample}"
        )

    full_refresh = not dinos

    if dinos:
        fossil_ids = [row.fossil_id for row in fossil_rows]
        if fossil_ids:
            session.exec(delete(FossilClean).where(col(FossilClean.fossil_id).in_(fossil_ids)))
        site_type_ids = _write_site_types(session, site_type_pairs, full_refresh=False)
        period_to_ids = period_to_type_ids(load_site_types_by_period(session))
        site_rows = _finalize_site_rows(site_drafts, site_type_ids, period_to_ids)
        for site_row in site_rows:
            session.merge(site_row)
        session.flush()
        for fossil_row in fossil_rows:
            session.add(fossil_row)
    else:
        session.exec(delete(FossilClean))
        session.exec(delete(SiteClean))
        site_type_ids = _write_site_types(session, site_type_pairs, full_refresh=True)
        period_to_ids = period_to_type_ids(load_site_types_by_period(session))
        site_rows = _finalize_site_rows(site_drafts, site_type_ids, period_to_ids)
        for site_row in site_rows:
            session.add(site_row)
        session.flush()
        for fossil_row in fossil_rows:
            session.add(fossil_row)

    session.commit()

    return summary


def sync_exit_code(summary: SyncSummary) -> int:
    if summary.counters.fossils_skipped > 0:
        return 1
    return 0
