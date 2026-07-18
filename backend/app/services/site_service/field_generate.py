"""Generate procedural field sites from archive-site geology patterns."""

from __future__ import annotations

import logging
import random
import time
from dataclasses import dataclass, field
from decimal import Decimal

from sqlalchemy import delete, func
from sqlmodel import Session, col, select

from app.models.data_source import DATA_SOURCE_ARCHIVE, DATA_SOURCE_FIELD
from app.models.site import Site
from app.models.site_type import SiteType
from app.services.site_service.field_coordinates import (
    CoordinateSampleConfig,
    LandMask,
    load_land_mask,
)
from app.services.site_service.field_distributions import (
    ArchiveSiteRef,
    DistributionWeights,
    blend_distributions,
    build_global_distribution,
    closest_distribution,
    nearby_distribution,
    sample_pair,
)
from app.services.site_service.reverse_geocode import lookup_country_state

logger = logging.getLogger("field_site_generate")

FIELD_SITE_ID_START = 1_000_000_000


@dataclass(frozen=True)
class FieldSiteGenerateConfig:
    max_items: int = 100
    refresh: bool = False

    nearby_radius_km: float = 100.0
    closest_neighbor_count: int = 20

    weight_global: float = 0.25
    weight_nearby: float = 0.50
    weight_closest: float = 0.25

    max_coordinate_attempts: int = 200
    min_separation_km: float = 1.0

    exclude_military: bool = False
    land_mask_path: str | None = None

    def validate(self) -> None:
        if self.max_items <= 0:
            raise ValueError("max_items must be positive")
        if self.closest_neighbor_count <= 0:
            raise ValueError("closest_neighbor_count must be positive")
        if self.nearby_radius_km <= 0:
            raise ValueError("nearby_radius_km must be positive")
        total = self.weight_global + self.weight_nearby + self.weight_closest
        if abs(total - 1.0) > 1e-6:
            raise ValueError("distribution weights must sum to 1.0")
        if self.exclude_military:
            logger.warning(
                "exclude_military=true is not implemented yet; using land-only sampling"
            )

    @property
    def coordinate_config(self) -> CoordinateSampleConfig:
        return CoordinateSampleConfig(
            max_coordinate_attempts=self.max_coordinate_attempts,
            min_separation_km=self.min_separation_km,
        )

    @property
    def distribution_weights(self) -> DistributionWeights:
        return DistributionWeights(
            global_weight=self.weight_global,
            nearby_weight=self.weight_nearby,
            closest_weight=self.weight_closest,
        )


@dataclass
class FieldSiteGenerateCounters:
    generated: int = 0
    skipped_coords: int = 0
    skipped_no_site_type: int = 0
    deleted_on_refresh: int = 0


@dataclass
class FieldSiteGenerateSummary:
    counters: FieldSiteGenerateCounters = field(default_factory=FieldSiteGenerateCounters)
    dry_run: bool = False
    elapsed_s: float = 0.0


def _load_archive_sites(session: Session) -> list[ArchiveSiteRef]:
    stmt = select(Site).where(col(Site.data_source) == DATA_SOURCE_ARCHIVE)
    rows = session.exec(stmt).all()
    refs: list[ArchiveSiteRef] = []
    for row in rows:
        if row.latitude is None or row.longitude is None:
            continue
        period = (row.period or "").strip()
        rock_type = (row.rock_type or "").strip()
        if not period or not rock_type:
            continue
        refs.append(
            ArchiveSiteRef(
                latitude=float(row.latitude),
                longitude=float(row.longitude),
                period=period,
                rock_type=rock_type,
            )
        )
    return refs


def _load_site_type_map(session: Session) -> dict[tuple[str, str], int]:
    mapping: dict[tuple[str, str], int] = {}
    for row in session.exec(select(SiteType)).all():
        if row.id is None:
            continue
        mapping[(row.period, row.rock_type)] = row.id
    return mapping


def _load_existing_field_coords(session: Session) -> list[tuple[float, float]]:
    stmt = select(Site).where(col(Site.data_source) == DATA_SOURCE_FIELD)
    coords: list[tuple[float, float]] = []
    for row in session.exec(stmt).all():
        if row.latitude is None or row.longitude is None:
            continue
        coords.append((float(row.latitude), float(row.longitude)))
    return coords


def _next_field_site_id(session: Session) -> int:
    current_max = session.exec(
        select(func.max(Site.site_id)).where(col(Site.data_source) == DATA_SOURCE_FIELD)
    ).one()
    if current_max is None:
        return FIELD_SITE_ID_START
    return max(int(current_max) + 1, FIELD_SITE_ID_START)


def _delete_field_sites(session: Session) -> int:
    existing = list(
        session.exec(select(Site.site_id).where(col(Site.data_source) == DATA_SOURCE_FIELD)).all()
    )
    if not existing:
        return 0
    session.exec(delete(Site).where(col(Site.data_source) == DATA_SOURCE_FIELD))
    session.flush()
    return len(existing)


def generate_field_sites(
    session: Session,
    *,
    config: FieldSiteGenerateConfig,
    dry_run: bool = False,
    rng: random.Random | None = None,
    land_mask: LandMask | None = None,
) -> FieldSiteGenerateSummary:
    """Create up to ``max_items`` procedural field sites."""
    started = time.monotonic()
    config.validate()
    random_source = rng or random.Random()

    archive_sites = _load_archive_sites(session)
    if not archive_sites:
        raise RuntimeError("No archive sites with coordinates, period, and rock_type found")

    site_type_map = _load_site_type_map(session)
    if not site_type_map:
        raise RuntimeError("No site_type rows found; run site_type_sync first")

    global_counts = build_global_distribution(archive_sites)
    mask = land_mask or load_land_mask(config.land_mask_path)
    existing_coords = _load_existing_field_coords(session)

    counters = FieldSiteGenerateCounters()
    if config.refresh:
        if dry_run:
            counters.deleted_on_refresh = len(existing_coords)
            existing_coords = []
        else:
            counters.deleted_on_refresh = _delete_field_sites(session)
            existing_coords = []

    next_site_id = _next_field_site_id(session)
    pending_rows: list[Site] = []

    for _ in range(config.max_items):
        sampled = mask.sample(
            existing=existing_coords,
            config=config.coordinate_config,
            rng=random_source,
        )
        if sampled is None:
            counters.skipped_coords += 1
            continue

        lat, lon = sampled
        nearby_counts = nearby_distribution(
            archive_sites,
            lat=lat,
            lon=lon,
            radius_km=config.nearby_radius_km,
        )
        closest_counts = closest_distribution(
            archive_sites,
            lat=lat,
            lon=lon,
            neighbor_count=config.closest_neighbor_count,
        )
        blended = blend_distributions(
            global_counts=global_counts,
            nearby_counts=nearby_counts,
            closest_counts=closest_counts,
            weights=config.distribution_weights,
        )
        pair = sample_pair(blended, rng=random_source)
        if pair is None:
            counters.skipped_no_site_type += 1
            continue

        period, rock_type = pair
        site_type_id = site_type_map.get(pair)
        if site_type_id is None:
            counters.skipped_no_site_type += 1
            logger.warning(
                "No site_type for period=%s rock_type=%s; skipping coordinate lat=%s lon=%s",
                period,
                rock_type,
                lat,
                lon,
            )
            continue

        country_code, state = lookup_country_state(lat, lon)
        site = Site(
            site_id=next_site_id,
            latitude=Decimal(str(round(lat, 6))),
            longitude=Decimal(str(round(lon, 6))),
            country_code=country_code,
            state=state,
            rock_type=rock_type,
            formation=None,
            min_age_ma=None,
            max_age_ma=None,
            period=period,
            site_type_id=site_type_id,
            data_source=DATA_SOURCE_FIELD,
        )
        next_site_id += 1
        existing_coords.append((lat, lon))
        counters.generated += 1

        if dry_run:
            continue

        pending_rows.append(site)
        if len(pending_rows) >= 500:
            session.add_all(pending_rows)
            session.flush()
            pending_rows.clear()

    if not dry_run and pending_rows:
        session.add_all(pending_rows)
        session.flush()
        session.commit()
    elif not dry_run:
        session.commit()

    summary = FieldSiteGenerateSummary(
        counters=counters,
        dry_run=dry_run,
        elapsed_s=time.monotonic() - started,
    )
    logger.info(
        "%s action=summary generated=%d skipped_coords=%d skipped_no_site_type=%d "
        "deleted_on_refresh=%d dry_run=%s elapsed_s=%.2f",
        "field_site_generate",
        counters.generated,
        counters.skipped_coords,
        counters.skipped_no_site_type,
        counters.deleted_on_refresh,
        dry_run,
        summary.elapsed_s,
    )
    return summary


def field_site_generate_exit_code(summary: FieldSiteGenerateSummary) -> int:
    if summary.counters.generated == 0 and not summary.dry_run:
        return 1
    return 0


def config_from_params(params: dict) -> FieldSiteGenerateConfig:
    """Build config from cron YAML/CLI params, falling back to defaults."""
    defaults = FieldSiteGenerateConfig()
    max_items = params.get("max_items")
    return FieldSiteGenerateConfig(
        max_items=int(max_items) if max_items is not None else defaults.max_items,
        refresh=bool(params.get("refresh", defaults.refresh)),
        nearby_radius_km=float(params.get("nearby_radius_km", defaults.nearby_radius_km)),
        closest_neighbor_count=int(
            params.get("closest_neighbor_count", defaults.closest_neighbor_count)
        ),
        weight_global=float(params.get("weight_global", defaults.weight_global)),
        weight_nearby=float(params.get("weight_nearby", defaults.weight_nearby)),
        weight_closest=float(params.get("weight_closest", defaults.weight_closest)),
        max_coordinate_attempts=int(
            params.get("max_coordinate_attempts", defaults.max_coordinate_attempts)
        ),
        min_separation_km=float(params.get("min_separation_km", defaults.min_separation_km)),
        exclude_military=bool(params.get("exclude_military", defaults.exclude_military)),
        land_mask_path=params.get("land_mask_path"),
    )
