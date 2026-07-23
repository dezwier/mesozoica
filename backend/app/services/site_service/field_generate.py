"""Generate procedural field sites from archive-site geology patterns."""

from __future__ import annotations

import logging
import random
import time
from collections import Counter
from dataclasses import dataclass, field
from decimal import Decimal

from sqlalchemy import func, text
from sqlalchemy.orm import aliased
from sqlmodel import Session, col, delete, select

from app.core.database import engine
from app.core.game_config import SiteGenerationConfig, get_game_config

from app.models.data_source import DATA_SOURCE_ARCHIVE, DATA_SOURCE_FIELD
from app.models.site import Site
from app.models.site_type import SiteType
from app.models.user_site import (
    SITE_STATUS_EXHAUSTED,
    UserSite,
    role_to_status,
)
from app.services.site_service.field_coordinate_filter import (
    CoordinateSampleConfig,
    CoordinateSampler,
    build_coordinate_sampler,
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
from app.services.site_service.field_site_logging import log_field_event
from app.services.site_service.geo_utils import haversine_km
from app.services.site_service.nearby import (
    _bbox,
    count_sites_in_radius,
    list_sites_in_radius,
)
from app.services.site_service.status_join import (
    latest_user_site_join_condition,
    latest_user_site_subquery,
)
from app.services.site_service.summary import SiteRow

logger = logging.getLogger("field_site_generate")

_LatestUserSite = aliased(UserSite)
FIELD_SITE_ID_START = 1_000_000_000
PROGRESS_LOG_INTERVAL = 100
WRITE_BATCH_SIZE = 5


def _site_gen() -> SiteGenerationConfig:
    return get_game_config().site_generation


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
    min_separation_km: float = 0.01

    exclude_military: bool = False
    land_mask_path: str | None = None

    @classmethod
    def from_game_config(
        cls,
        *,
        refresh: bool = False,
        exclude_military: bool = False,
        land_mask_path: str | None = None,
        max_items: int | None = None,
    ) -> FieldSiteGenerateConfig:
        bulk = _site_gen().bulk
        return cls(
            max_items=bulk.max_items if max_items is None else max_items,
            refresh=refresh,
            nearby_radius_km=bulk.nearby_radius_km,
            closest_neighbor_count=bulk.closest_neighbor_count,
            weight_global=bulk.weight_global,
            weight_nearby=bulk.weight_nearby,
            weight_closest=bulk.weight_closest,
            max_coordinate_attempts=bulk.max_coordinate_attempts,
            min_separation_km=bulk.min_separation_km,
            exclude_military=exclude_military,
            land_mask_path=land_mask_path,
        )

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


@dataclass(frozen=True)
class FieldSiteLazyConfig:
    min_sites_in_radius: int = 100
    radius_km: float = 1.0
    min_separation_km: float = 0.01

    nearby_radius_km: float = 100.0
    closest_neighbor_count: int = 20

    weight_global: float = 0.25
    weight_nearby: float = 0.50
    weight_closest: float = 0.25

    max_coordinate_attempts: int = 200
    exclude_military: bool = False
    land_mask_path: str | None = None

    @classmethod
    def from_game_config(
        cls,
        *,
        radius_km: float | None = None,
        exclude_military: bool = False,
        land_mask_path: str | None = None,
    ) -> FieldSiteLazyConfig:
        lazy = _site_gen().lazy
        return cls(
            min_sites_in_radius=lazy.min_sites_in_radius,
            radius_km=lazy.radius_km if radius_km is None else radius_km,
            min_separation_km=lazy.min_separation_km,
            nearby_radius_km=lazy.nearby_radius_km,
            closest_neighbor_count=lazy.closest_neighbor_count,
            weight_global=lazy.weight_global,
            weight_nearby=lazy.weight_nearby,
            weight_closest=lazy.weight_closest,
            max_coordinate_attempts=lazy.max_coordinate_attempts,
            exclude_military=exclude_military,
            land_mask_path=land_mask_path,
        )

    def validate(self) -> None:
        if self.min_sites_in_radius <= 0:
            raise ValueError("min_sites_in_radius must be positive")
        if self.radius_km <= 0:
            raise ValueError("radius_km must be positive")
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
class EnsureFieldSitesResult:
    generated: int
    total_in_radius: int
    skipped_coords: int
    skipped_no_site_type: int
    items: list[SiteRow]
    radius_km: float


@dataclass
class _GenerationContext:
    archive_sites: list[ArchiveSiteRef]
    global_counts: Counter[tuple[str, str]]
    site_type_map: dict[tuple[str, str], int]
    sampler: CoordinateSampler
    distribution_weights: DistributionWeights
    nearby_radius_km: float
    closest_neighbor_count: int


def _build_generation_context(
    session: Session,
    *,
    coordinate_sampler: CoordinateSampler | None = None,
    land_mask_path: str | None = None,
    exclude_military: bool = False,
    distribution_weights: DistributionWeights,
    nearby_radius_km: float,
    closest_neighbor_count: int,
) -> _GenerationContext:
    archive_sites = _load_archive_sites(session)
    if not archive_sites:
        raise RuntimeError("No archive sites with coordinates, period, and rock_type found")

    site_type_map = _load_site_type_map(session)
    if not site_type_map:
        raise RuntimeError("No site_type rows found; run site_type_sync first")

    global_counts = build_global_distribution(archive_sites)
    sampler = coordinate_sampler or build_coordinate_sampler(
        land_mask_path=land_mask_path,
        exclude_military=exclude_military,
    )
    return _GenerationContext(
        archive_sites=archive_sites,
        global_counts=global_counts,
        site_type_map=site_type_map,
        sampler=sampler,
        distribution_weights=distribution_weights,
        nearby_radius_km=nearby_radius_km,
        closest_neighbor_count=closest_neighbor_count,
    )


def _build_field_site(
    context: _GenerationContext,
    *,
    lat: float,
    lon: float,
    site_id: int,
    rng: random.Random,
) -> Site | None:
    nearby_counts = nearby_distribution(
        context.archive_sites,
        lat=lat,
        lon=lon,
        radius_km=context.nearby_radius_km,
    )
    closest_counts = closest_distribution(
        context.archive_sites,
        lat=lat,
        lon=lon,
        neighbor_count=context.closest_neighbor_count,
    )
    blended = blend_distributions(
        global_counts=context.global_counts,
        nearby_counts=nearby_counts,
        closest_counts=closest_counts,
        weights=context.distribution_weights,
    )
    pair = sample_pair(blended, rng=rng)
    if pair is None:
        return None

    period, rock_type = pair
    site_type_id = context.site_type_map.get(pair)
    if site_type_id is None:
        logger.warning(
            "No site_type for period=%s rock_type=%s; skipping coordinate lat=%s lon=%s",
            period,
            rock_type,
            lat,
            lon,
        )
        return None

    return Site(
        site_id=site_id,
        latitude=Decimal(str(round(lat, 6))),
        longitude=Decimal(str(round(lon, 6))),
        country_code=None,
        state=None,
        rock_type=rock_type,
        formation=None,
        min_age_ma=None,
        max_age_ma=None,
        period=period,
        site_type_id=site_type_id,
        data_source=DATA_SOURCE_FIELD,
        odd_dino_count=rng.random(),
        odd_fossil_count=rng.random(),
        odd_completeness=rng.random(),
        odd_quality=rng.random(),
        odd_depth=rng.random(),
    )


def _flush_pending_sites(session: Session, pending_rows: list[Site]) -> None:
    if not pending_rows:
        return
    session.add_all(pending_rows)
    session.commit()
    pending_rows.clear()


def _allocate_field_site_ids(session: Session, count: int) -> list[int]:
    """Reserve ``count`` field site IDs in a short transaction."""
    if count <= 0:
        return []
    allocator = _FieldSiteIdAllocator(session)
    ids = [allocator.next_id() for _ in range(count)]
    session.commit()
    return ids


def ensure_field_sites_nearby(
    session: Session,
    *,
    lat: float,
    lon: float,
    config: FieldSiteLazyConfig | None = None,
    rng: random.Random | None = None,
    coordinate_sampler: CoordinateSampler | None = None,
) -> EnsureFieldSitesResult:
    """Top up non-exhausted field sites within ``radius_km`` to ``min_sites_in_radius``.

    Exhausted sites are ignored for both the density quota and min-separation
    coordinate blocking, so new ``hidden`` sites can replace them as others
    become exhausted.

    Short DB transactions: read → commit, then sample and commit every
    ``WRITE_BATCH_SIZE`` sites so the map can poll progressive batches.
    """
    cfg = config or FieldSiteLazyConfig.from_game_config()
    cfg.validate()
    random_source = rng or random.Random()

    # --- Short read transaction ---
    context = _build_generation_context(
        session,
        coordinate_sampler=coordinate_sampler,
        land_mask_path=cfg.land_mask_path,
        exclude_military=cfg.exclude_military,
        distribution_weights=cfg.distribution_weights,
        nearby_radius_km=cfg.nearby_radius_km,
        closest_neighbor_count=cfg.closest_neighbor_count,
    )

    existing_count = count_sites_in_radius(
        session,
        lat=lat,
        lon=lon,
        radius_km=cfg.radius_km,
        data_source=DATA_SOURCE_FIELD,
    )
    missing = max(0, cfg.min_sites_in_radius - existing_count)

    if missing == 0:
        items = list_sites_in_radius(
            session,
            lat=lat,
            lon=lon,
            radius_km=cfg.radius_km,
            data_source=DATA_SOURCE_FIELD,
            show_all=True,
        )
        session.commit()
        return EnsureFieldSitesResult(
            generated=0,
            # Density metric: non-exhausted only (may be < len(items) if some
            # are exhausted).
            total_in_radius=existing_count,
            skipped_coords=0,
            skipped_no_site_type=0,
            items=items,
            radius_km=cfg.radius_km,
        )

    _sync_field_site_id_sequence(session)
    existing_coords = _load_existing_field_coords(
        session,
        lat=lat,
        lon=lon,
        radius_km=cfg.radius_km,
        min_separation_km=cfg.min_separation_km,
    )
    session.commit()

    # --- Short ID reservation ---
    candidate_ids = _allocate_field_site_ids(session, missing)
    id_iter = iter(candidate_ids)

    # --- Sample + commit progressively (short write txns) ---
    pending_rows: list[Site] = []
    generated = 0
    skipped_coords = 0
    skipped_no_site_type = 0
    max_attempts = missing * cfg.max_coordinate_attempts

    for _ in range(max_attempts):
        if generated >= missing:
            break

        sampled = context.sampler.sample_in_radius(
            center_lat=lat,
            center_lon=lon,
            radius_km=cfg.radius_km,
            existing=existing_coords,
            config=cfg.coordinate_config,
            rng=random_source,
        )
        if sampled is None:
            skipped_coords += 1
            continue

        try:
            site_id = next(id_iter)
        except StopIteration:
            break

        site_lat, site_lon = sampled
        site = _build_field_site(
            context,
            lat=site_lat,
            lon=site_lon,
            site_id=site_id,
            rng=random_source,
        )
        if site is None:
            skipped_no_site_type += 1
            continue

        existing_coords.append((site_lat, site_lon))
        pending_rows.append(site)
        generated += 1

        if len(pending_rows) >= WRITE_BATCH_SIZE:
            _flush_pending_sites(session, pending_rows)

    _flush_pending_sites(session, pending_rows)

    items = list_sites_in_radius(
        session,
        lat=lat,
        lon=lon,
        radius_km=cfg.radius_km,
        data_source=DATA_SOURCE_FIELD,
        show_all=True,
    )
    # Same metric as density top-up: non-exhausted field sites only.
    total_in_radius = count_sites_in_radius(
        session,
        lat=lat,
        lon=lon,
        radius_km=cfg.radius_km,
        data_source=DATA_SOURCE_FIELD,
    )
    session.commit()
    return EnsureFieldSitesResult(
        generated=generated,
        total_in_radius=total_in_radius,
        skipped_coords=skipped_coords,
        skipped_no_site_type=skipped_no_site_type,
        items=items,
        radius_km=cfg.radius_km,
    )


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


def _load_existing_field_coords(
    session: Session,
    *,
    lat: float | None = None,
    lon: float | None = None,
    radius_km: float | None = None,
    min_separation_km: float = 0.01,
) -> list[tuple[float, float]]:
    """Coords of non-exhausted field sites used for min-separation sampling."""
    max_ts = latest_user_site_subquery()
    stmt = (
        select(Site, _LatestUserSite)
        .outerjoin(max_ts, col(Site.site_id) == max_ts.c.site_id)
        .outerjoin(
            _LatestUserSite,
            latest_user_site_join_condition(_LatestUserSite, max_ts),
        )
        .where(col(Site.data_source) == DATA_SOURCE_FIELD)
    )
    if lat is not None and lon is not None and radius_km is not None:
        search_radius = radius_km + min_separation_km
        min_lat, max_lat, min_lon, max_lon = _bbox(lat, lon, search_radius)
        stmt = stmt.where(
            col(Site.latitude).is_not(None),
            col(Site.longitude).is_not(None),
            col(Site.latitude) >= min_lat,
            col(Site.latitude) <= max_lat,
            col(Site.longitude) >= min_lon,
            col(Site.longitude) <= max_lon,
        )
    coords: list[tuple[float, float]] = []
    for site, latest_user_site in session.exec(stmt).all():
        if site.latitude is None or site.longitude is None:
            continue
        status = role_to_status(
            latest_user_site.role if latest_user_site is not None else None
        )
        if status == SITE_STATUS_EXHAUSTED:
            continue
        site_lat = float(site.latitude)
        site_lon = float(site.longitude)
        if lat is not None and lon is not None and radius_km is not None:
            if haversine_km(lat, lon, site_lat, site_lon) > radius_km + min_separation_km:
                continue
        coords.append((site_lat, site_lon))
    return coords


def _sync_field_site_id_sequence(session: Session) -> None:
    """Advance the Postgres sequence past existing field site IDs."""
    if engine.dialect.name != "postgresql":
        return
    session.exec(
        text(
            """
            SELECT setval(
                'field_site_id_seq',
                GREATEST(
                    :start,
                    COALESCE(
                        (SELECT MAX(site_id) FROM site WHERE site_id >= :start),
                        :start_minus_one
                    )
                ),
                true
            )
            """
        ).bindparams(
            start=FIELD_SITE_ID_START,
            start_minus_one=FIELD_SITE_ID_START - 1,
        )
    )


class _FieldSiteIdAllocator:
    """Hand out unique field site IDs (Postgres sequence or SQLite counter)."""

    def __init__(self, session: Session) -> None:
        self._session = session
        self._sqlite_next: int | None = None

    def next_id(self) -> int:
        if engine.dialect.name == "postgresql":
            row = self._session.exec(
                text("SELECT nextval('field_site_id_seq')")
            ).one()
            return max(int(row[0]), FIELD_SITE_ID_START)

        if self._sqlite_next is None:
            current_max = self._session.exec(
                select(func.max(Site.site_id)).where(
                    col(Site.site_id) >= FIELD_SITE_ID_START
                )
            ).one()
            if current_max is None:
                self._sqlite_next = FIELD_SITE_ID_START
            else:
                self._sqlite_next = max(int(current_max) + 1, FIELD_SITE_ID_START)
        next_id = self._sqlite_next
        self._sqlite_next += 1
        return next_id


def _next_field_site_id(session: Session) -> int:
    return _FieldSiteIdAllocator(session).next_id()


def _delete_field_sites(session: Session) -> int:
    existing = list(
        session.exec(select(Site.site_id).where(col(Site.data_source) == DATA_SOURCE_FIELD)).all()
    )
    if not existing:
        return 0
    session.exec(delete(Site).where(col(Site.data_source) == DATA_SOURCE_FIELD))
    session.flush()
    return len(existing)


def _log_progress(
    counters: FieldSiteGenerateCounters,
    max_items: int,
    started: float,
) -> None:
    elapsed_s = time.monotonic() - started
    logger.info(
        "%s action=progress generated=%d/%d skipped_coords=%d skipped_no_site_type=%d "
        "elapsed_s=%.1f",
        "field_site_generate",
        counters.generated,
        max_items,
        counters.skipped_coords,
        counters.skipped_no_site_type,
        elapsed_s,
    )


def _write_pending_batch(
    session: Session,
    pending_rows: list[Site],
    *,
    counters: FieldSiteGenerateCounters,
    max_items: int,
    started: float,
) -> None:
    if not pending_rows:
        return
    session.add_all(pending_rows)
    session.flush()
    session.commit()
    pending_rows.clear()
    _log_progress(counters, max_items, started)


def generate_field_sites(
    session: Session,
    *,
    config: FieldSiteGenerateConfig,
    dry_run: bool = False,
    rng: random.Random | None = None,
    coordinate_sampler: CoordinateSampler | None = None,
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
    sampler = coordinate_sampler or build_coordinate_sampler(
        land_mask_path=config.land_mask_path,
        exclude_military=config.exclude_military,
    )
    existing_coords = _load_existing_field_coords(session)

    logger.info(
        "%s action=start max_items=%d refresh=%s dry_run=%s archive_sites=%d "
        "site_types=%d existing_field_sites=%d",
        "field_site_generate",
        config.max_items,
        config.refresh,
        dry_run,
        len(archive_sites),
        len(site_type_map),
        len(existing_coords),
    )

    counters = FieldSiteGenerateCounters()
    if config.refresh:
        if dry_run:
            counters.deleted_on_refresh = len(existing_coords)
            existing_coords = []
        else:
            counters.deleted_on_refresh = _delete_field_sites(session)
            existing_coords = []
        if counters.deleted_on_refresh:
            logger.info(
                "%s action=refresh deleted_field_sites=%d dry_run=%s",
                "field_site_generate",
                counters.deleted_on_refresh,
                dry_run,
            )

    _sync_field_site_id_sequence(session)
    id_allocator = _FieldSiteIdAllocator(session)
    pending_rows: list[Site] = []

    for _ in range(config.max_items):
        sampled = sampler.sample(
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

        site = Site(
            site_id=id_allocator.next_id(),
            latitude=Decimal(str(round(lat, 6))),
            longitude=Decimal(str(round(lon, 6))),
            country_code=None,
            state=None,
            rock_type=rock_type,
            formation=None,
            min_age_ma=None,
            max_age_ma=None,
            period=period,
            site_type_id=site_type_id,
            data_source=DATA_SOURCE_FIELD,
            odd_dino_count=random_source.random(),
            odd_fossil_count=random_source.random(),
            odd_completeness=random_source.random(),
            odd_quality=random_source.random(),
            odd_depth=random_source.random(),
        )
        existing_coords.append((lat, lon))
        counters.generated += 1

        if dry_run:
            if counters.generated % PROGRESS_LOG_INTERVAL == 0:
                _log_progress(counters, config.max_items, started)
            continue

        pending_rows.append(site)
        if counters.generated % PROGRESS_LOG_INTERVAL == 0:
            _write_pending_batch(
                session,
                pending_rows,
                counters=counters,
                max_items=config.max_items,
                started=started,
            )

    if not dry_run:
        _write_pending_batch(
            session,
            pending_rows,
            counters=counters,
            max_items=config.max_items,
            started=started,
        )
    elif counters.generated > 0 and counters.generated % PROGRESS_LOG_INTERVAL != 0:
        _log_progress(counters, config.max_items, started)

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
    """Build config from cron YAML/CLI params, falling back to game_config defaults."""
    defaults = FieldSiteGenerateConfig.from_game_config()
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
