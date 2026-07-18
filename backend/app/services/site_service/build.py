"""Shared helpers for building site rows from fossil data."""

from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass

from sqlmodel import Session, col, select

from app.models.dinosaur import Dinosaur
from app.models.data_source import DATA_SOURCE_ARCHIVE
from app.models.fossil import Fossil
from app.models.site import Site
from app.services.dinosaur_name_filter import dino_name_match_clause
from app.services.site_service.rules import (
    ages_for_site,
    formation_for_site,
    period_for_ages,
    rock_type_for_site,
)


@dataclass
class SiteDraft:
    site: Site


def fossil_query(session: Session, *, dinos: list[str] | None):
    stmt = select(Fossil).where(col(Fossil.data_source) == DATA_SOURCE_ARCHIVE)
    if dinos:
        stmt = stmt.join(Dinosaur, col(Fossil.dinosaur_id) == col(Dinosaur.id)).where(
            dino_name_match_clause(dinos)
        )
    return stmt


def site_members(session: Session, collection_nos: set[int]) -> dict[int, list[Fossil]]:
    if not collection_nos:
        return {}
    stmt = select(Fossil).where(
        col(Fossil.collection_no).in_(collection_nos),
        col(Fossil.data_source) == DATA_SOURCE_ARCHIVE,
    )
    grouped: dict[int, list[Fossil]] = defaultdict(list)
    for fossil in session.exec(stmt).all():
        if fossil.collection_no is not None:
            grouped[fossil.collection_no].append(fossil)
    return grouped


def build_site_draft(site_id: int, fossils_at_site: list[Fossil]) -> SiteDraft | None:
    if not fossils_at_site:
        return None
    ref = fossils_at_site[0]
    min_age_ma, max_age_ma = ages_for_site(fossils_at_site)
    return SiteDraft(
        site=Site(
            site_id=site_id,
            latitude=ref.latitude,
            longitude=ref.longitude,
            country_code=ref.country_code,
            state=ref.state,
            rock_type=rock_type_for_site(fossils_at_site),
            formation=formation_for_site(fossils_at_site),
            min_age_ma=min_age_ma,
            max_age_ma=max_age_ma,
            period=period_for_ages(min_age_ma, max_age_ma),
        ),
    )


def linkable_fossils(source_fossils: list[Fossil]) -> tuple[list[Fossil], int]:
    linkable: list[Fossil] = []
    skipped = 0
    for fossil in source_fossils:
        if fossil.collection_no is None:
            skipped += 1
            continue
        linkable.append(fossil)
    return linkable, skipped


def apply_site_draft(existing: Site, draft: Site) -> None:
    existing.latitude = draft.latitude
    existing.longitude = draft.longitude
    existing.country_code = draft.country_code
    existing.state = draft.state
    existing.rock_type = draft.rock_type
    existing.formation = draft.formation
    existing.min_age_ma = draft.min_age_ma
    existing.max_age_ma = draft.max_age_ma
    existing.period = draft.period
