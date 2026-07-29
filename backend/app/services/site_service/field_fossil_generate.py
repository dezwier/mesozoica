"""Sample and write field fossils for a discovered site (lazy, once per site)."""

from __future__ import annotations

import logging
import random
from collections import Counter
from dataclasses import dataclass
from typing import TypeVar

from sqlalchemy import text
from sqlmodel import Session, col, func, select

from app.core.game_config import (
    DinoCountThreshold,
    FossilDepthBucket,
    get_game_config,
)
from app.models.data_source import DATA_SOURCE_ARCHIVE, DATA_SOURCE_FIELD
from app.models.dinosaur_type import DinosaurType
from app.models.fossil import Fossil
from app.models.site import Site
from app.services.fossil_enrichment_service.validate import (
    BODY_SUBCATEGORIES,
    TRACE_SUBCATEGORIES,
    UNKNOWN,
)

logger = logging.getLogger(__name__)

FIELD_FOSSIL_ID_START = 1_000_000_000
_DEFAULT_ODD = 0.5
_T = TypeVar("_T")

# Worst → best for archive-biased CDF lookup.
COMPLETENESS_ORDER: tuple[str, ...] = (
    "trace_only",
    "isolated_element",
    "fragmentary",
    "partial",
    "substantial",
    "nearly_complete",
)
QUALITY_ORDER: tuple[str, ...] = (
    "very_poor",
    "poor",
    "moderate",
    "good",
    "excellent",
    "exceptional",
)


def _fossil_gen():
    return get_game_config().fossil_generation


@dataclass(frozen=True)
class FieldFossilGenerateResult:
    generated: int
    skipped: bool


def count_field_fossils_for_site(session: Session, site_id: int) -> int:
    return int(
        session.exec(
            select(func.count())
            .select_from(Fossil)
            .where(
                col(Fossil.site_id) == site_id,
                col(Fossil.data_source) == DATA_SOURCE_FIELD,
            )
        ).one()
    )


def clamp_odd(
    odd: float | None,
    noise: float,
    *,
    rng: random.Random,
) -> float:
    """score = clamp(odd + Uniform(-noise, +noise), 0, 1). Missing odd → 0.5."""
    base = _DEFAULT_ODD if odd is None else float(odd)
    score = base + rng.uniform(-noise, noise)
    return max(0.0, min(1.0, score))


def tier_from_cdf(
    score: float,
    items: list[_T],
    weights: list[float],
) -> _T:
    """Pick the tier whose cumulative weight first reaches ``score`` (inverse CDF)."""
    if not items:
        raise ValueError("tier_from_cdf requires at least one item")
    if len(items) != len(weights):
        raise ValueError("tier_from_cdf items/weights length mismatch")
    total = sum(weights)
    if total <= 0:
        return items[-1]
    cumulative = 0.0
    for item, weight in zip(items, weights):
        cumulative += weight / total
        if score <= cumulative:
            return item
    return items[-1]


def dino_count_from_score(
    score: float,
    thresholds: list[DinoCountThreshold],
) -> int:
    """Map score to count using exclusive upper bounds except the final tier."""
    if not thresholds:
        return 0
    for threshold in thresholds[:-1]:
        if score < threshold.max_odd:
            return threshold.count
    return thresholds[-1].count


def sample_depth_cm(
    buckets: list[FossilDepthBucket],
    *,
    score: float,
    rng: random.Random,
) -> int:
    """Sample burial depth via odd score against bucket CDF, then uniform in range."""
    bucket = tier_from_cdf(
        score,
        buckets,
        [b.weight for b in buckets],
    )
    if bucket.min_cm == bucket.max_cm:
        return bucket.min_cm
    return rng.randint(bucket.min_cm, bucket.max_cm)


def ensure_field_fossils_for_site(
    session: Session,
    *,
    site_id: int,
    rng: random.Random | None = None,
) -> FieldFossilGenerateResult:
    """Generate field fossils for ``site_id`` if none exist yet."""
    existing = count_field_fossils_for_site(session, site_id)
    if existing > 0:
        return FieldFossilGenerateResult(generated=0, skipped=True)

    site = session.get(Site, site_id)
    if site is None or site.data_source != DATA_SOURCE_FIELD:
        raise ValueError(f"Field site {site_id} not found")
    period = (site.period or "").strip().lower()
    rock_type = (site.rock_type or "").strip().lower()
    if not period or not rock_type:
        raise ValueError(f"Site {site_id} missing period/rock_type for fossil generation")

    random_source = rng or random.Random()
    fossil_cfg = _fossil_gen()
    noise = fossil_cfg.odd_noise

    dino_counts = _dino_distribution(session, period=period, rock_type=rock_type)
    if not dino_counts:
        logger.warning(
            "No archive dino distribution for period=%s rock_type=%s; skipping",
            period,
            rock_type,
        )
        return FieldFossilGenerateResult(generated=0, skipped=True)

    attr_dists = _attribute_distributions(session, period=period)
    dino_ids = _sample_dino_ids(
        dino_counts,
        odd=site.odd_dino_count,
        noise=noise.dino_count,
        thresholds=fossil_cfg.dino_count_thresholds,
        rng=random_source,
    )
    dino_names = _load_dino_names(session, dino_ids)

    _sync_field_fossil_id_sequence(session)
    id_allocator = _FieldFossilIdAllocator(session)

    pending: list[Fossil] = []
    for dinosaur_id in dino_ids:
        card_score = clamp_odd(
            site.odd_fossil_count, noise.fossil_count, rng=random_source
        )
        card_keys = sorted(fossil_cfg.card_count_weights.keys())
        card_count = tier_from_cdf(
            card_score,
            card_keys,
            [fossil_cfg.card_count_weights[k] for k in card_keys],
        )
        subcategories = _sample_distinct_subcategories(
            attr_dists.subcategory,
            count=card_count,
            default=fossil_cfg.defaults.subcategory,
            rng=random_source,
        )
        for subcategory in subcategories:
            completeness = _sample_ordered_from_counter(
                attr_dists.completeness,
                order=COMPLETENESS_ORDER,
                odd=site.odd_completeness,
                noise=noise.completeness,
                default=fossil_cfg.defaults.completeness,
                rng=random_source,
            )
            quality = _sample_ordered_from_counter(
                attr_dists.preservation_quality,
                order=QUALITY_ORDER,
                odd=site.odd_quality,
                noise=noise.quality,
                default=fossil_cfg.defaults.quality,
                rng=random_source,
            )
            category = _category_for_subcategory(subcategory)
            name = dino_names.get(dinosaur_id) or f"dinosaur-{dinosaur_id}"
            identified = f"{name} ({subcategory.replace('_', ' ')})"
            fossil_id = id_allocator.next_id()
            depth_score = clamp_odd(site.odd_depth, noise.depth, rng=random_source)
            depth_cm = sample_depth_cm(
                fossil_cfg.depth_buckets,
                score=depth_score,
                rng=random_source,
            )
            pending.append(
                Fossil(
                    id=fossil_id,
                    dinosaur_id=dinosaur_id,
                    site_id=site.site_id,
                    identified_name=identified,
                    genus=name,
                    latitude=site.latitude,
                    longitude=site.longitude,
                    country_code=site.country_code,
                    state=site.state,
                    geological_formation=site.formation,
                    min_age_ma=site.min_age_ma,
                    max_age_ma=site.max_age_ma,
                    llm_rock_type=rock_type,
                    llm_category=category,
                    llm_subcategory=subcategory,
                    llm_preservation_quality=quality,
                    llm_completeness=completeness,
                    llm_imp_rock_type=rock_type,
                    llm_imp_category=category,
                    llm_imp_subcategory=subcategory,
                    llm_imp_preservation_quality=quality,
                    llm_imp_completeness=completeness,
                    data_source=DATA_SOURCE_FIELD,
                    depth_cm=depth_cm,
                    llm_enriched=True,
                )
            )

    # Re-check under the same session before write (race with concurrent worker).
    if count_field_fossils_for_site(session, site_id) > 0:
        return FieldFossilGenerateResult(generated=0, skipped=True)

    session.add_all(pending)
    session.commit()
    return FieldFossilGenerateResult(generated=len(pending), skipped=False)


@dataclass(frozen=True)
class _AttributeDistributions:
    subcategory: Counter[str]
    completeness: Counter[str]
    preservation_quality: Counter[str]


def _dino_distribution(
    session: Session,
    *,
    period: str,
    rock_type: str,
) -> Counter[int]:
    pair_counts = _count_dinos_by_site_geology(
        session, period=period, rock_type=rock_type
    )
    if pair_counts:
        return pair_counts
    period_counts = _count_dinos_by_site_geology(session, period=period, rock_type=None)
    if period_counts:
        return period_counts
    return _count_dinos_by_site_geology(session, period=None, rock_type=None)


def _count_dinos_by_site_geology(
    session: Session,
    *,
    period: str | None,
    rock_type: str | None,
) -> Counter[int]:
    stmt = (
        select(col(Fossil.dinosaur_id), func.count())
        .join(Site, col(Site.site_id) == col(Fossil.site_id))
        .where(
            col(Fossil.data_source) == DATA_SOURCE_ARCHIVE,
            col(Site.data_source) == DATA_SOURCE_ARCHIVE,
            col(Fossil.dinosaur_id).is_not(None),
        )
        .group_by(col(Fossil.dinosaur_id))
    )
    if period is not None:
        stmt = stmt.where(func.lower(col(Site.period)) == period)
    if rock_type is not None:
        stmt = stmt.where(func.lower(col(Site.rock_type)) == rock_type)
    rows = session.exec(stmt).all()
    return Counter({int(dino_id): int(count) for dino_id, count in rows if dino_id})


def _attribute_distributions(
    session: Session, *, period: str
) -> _AttributeDistributions:
    rows = session.exec(
        select(
            Fossil.llm_imp_subcategory,
            Fossil.llm_imp_completeness,
            Fossil.llm_imp_preservation_quality,
        )
        .join(Site, col(Site.site_id) == col(Fossil.site_id))
        .where(
            col(Fossil.data_source) == DATA_SOURCE_ARCHIVE,
            col(Site.data_source) == DATA_SOURCE_ARCHIVE,
            func.lower(col(Site.period)) == period,
        )
    ).all()

    subcategory: Counter[str] = Counter()
    completeness: Counter[str] = Counter()
    quality: Counter[str] = Counter()
    for sub, comp, qual in rows:
        _bump_if_known(subcategory, sub)
        _bump_if_known(completeness, comp)
        _bump_if_known(quality, qual)
    return _AttributeDistributions(
        subcategory=subcategory,
        completeness=completeness,
        preservation_quality=quality,
    )


def _bump_if_known(counter: Counter[str], value: str | None) -> None:
    if value is None:
        return
    normalized = value.strip().lower()
    if not normalized or normalized == UNKNOWN:
        return
    counter[normalized] += 1


def _sample_dino_ids(
    counts: Counter[int],
    *,
    odd: float | None,
    noise: float,
    thresholds: list[DinoCountThreshold],
    rng: random.Random,
) -> list[int]:
    score = clamp_odd(odd, noise, rng=rng)
    target = dino_count_from_score(score, thresholds)
    target = min(target, len(counts))
    if target <= 0:
        return []
    pool = dict(counts)
    chosen: list[int] = []
    for _ in range(target):
        if not pool:
            break
        keys = list(pool.keys())
        weights = [pool[k] for k in keys]
        pick = rng.choices(keys, weights=weights, k=1)[0]
        chosen.append(pick)
        del pool[pick]
    return chosen


def _sample_from_counter(
    counts: Counter[str],
    *,
    default: str,
    rng: random.Random,
) -> str:
    if not counts:
        return default
    keys = list(counts.keys())
    weights = [counts[k] for k in keys]
    return str(rng.choices(keys, weights=weights, k=1)[0])


def _sample_distinct_subcategories(
    counts: Counter[str],
    *,
    count: int,
    default: str,
    rng: random.Random,
) -> list[str]:
    """Weighted sample without replacement so one dino never repeats a subcategory."""
    if count <= 0:
        return []

    pool = {key: weight for key, weight in counts.items() if weight > 0}
    chosen: list[str] = []
    for _ in range(count):
        if not pool:
            break
        keys = list(pool.keys())
        weights = [pool[k] for k in keys]
        pick = str(rng.choices(keys, weights=weights, k=1)[0])
        chosen.append(pick)
        del pool[pick]

    if len(chosen) >= count:
        return chosen

    # Top up from known body/trace subcategories if archive pool was too small.
    extras = [
        key
        for key in list(BODY_SUBCATEGORIES) + list(TRACE_SUBCATEGORIES)
        if key not in chosen
    ]
    rng.shuffle(extras)
    for key in extras:
        if len(chosen) >= count:
            break
        chosen.append(key)

    if not chosen:
        return [default]
    return chosen


def _sample_ordered_from_counter(
    counts: Counter[str],
    *,
    order: tuple[str, ...],
    odd: float | None,
    noise: float,
    default: str,
    rng: random.Random,
) -> str:
    """Bias archive frequencies with odd+noise via ordered inverse-CDF."""
    items = [key for key in order if counts.get(key, 0) > 0]
    if not items:
        extras = sorted(k for k in counts if k not in order and counts[k] > 0)
        items = extras
    if not items:
        return default
    score = clamp_odd(odd, noise, rng=rng)
    weights = [float(counts[k]) for k in items]
    return tier_from_cdf(score, items, weights)


def _category_for_subcategory(subcategory: str) -> str:
    if subcategory in TRACE_SUBCATEGORIES:
        return "trace"
    if subcategory in BODY_SUBCATEGORIES:
        return "body"
    return "body"


def _load_dino_names(session: Session, dino_ids: list[int]) -> dict[int, str]:
    if not dino_ids:
        return {}
    rows = session.exec(
        select(DinosaurType.id, DinosaurType.name).where(col(DinosaurType.id).in_(dino_ids))
    ).all()
    return {int(dino_id): name for dino_id, name in rows}


def _sync_field_fossil_id_sequence(session: Session) -> None:
    if session.get_bind().dialect.name != "postgresql":
        return
    session.execute(
        text(
            """
            SELECT setval(
                'field_fossil_id_seq',
                GREATEST(
                    (SELECT COALESCE(MAX(id), :start_minus_one) FROM fossil
                     WHERE id >= :start),
                    :start_minus_one
                ),
                true
            )
            """
        ),
        {"start": FIELD_FOSSIL_ID_START, "start_minus_one": FIELD_FOSSIL_ID_START - 1},
    )


class _FieldFossilIdAllocator:
    def __init__(self, session: Session) -> None:
        self._session = session
        self._sqlite_next: int | None = None

    def next_id(self) -> int:
        if self._session.get_bind().dialect.name == "postgresql":
            row = self._session.execute(
                text("SELECT nextval('field_fossil_id_seq')")
            ).one()
            return max(int(row[0]), FIELD_FOSSIL_ID_START)

        if self._sqlite_next is None:
            current_max = self._session.exec(
                select(func.max(Fossil.id)).where(
                    col(Fossil.id) >= FIELD_FOSSIL_ID_START
                )
            ).one()
            if current_max is None:
                self._sqlite_next = FIELD_FOSSIL_ID_START
            else:
                self._sqlite_next = max(int(current_max) + 1, FIELD_FOSSIL_ID_START)
        value = self._sqlite_next
        self._sqlite_next += 1
        return value
