"""Site identification quiz (period then rock type) after discovery."""

from __future__ import annotations

import hashlib
import random
from dataclasses import dataclass
from datetime import datetime, timezone

from sqlmodel import Session, col, select

from app.core.exceptions import NotFoundError, ValidationError
from app.models.data_source import DATA_SOURCE_FIELD
from app.models.site import Site
from app.models.site_type import SiteType
from app.models.user import User
from app.models.user_site import (
    USER_SITE_ROLE_DISCOVERER,
    USER_SITE_ROLE_IDENTIFIER,
    UserSite,
)
from app.schemas.auth import UserProfileResponse
from app.schemas.site import SiteSummary
from app.services.level_service import (
    award_site_identification_xp,
    get_skill_xp,
    level_for_xp,
)
from app.services.site_service.list import get_site_by_id
from app.services.site_service.summary import (
    enrich_site_rows_for_viewer,
    site_row_to_summary,
)
from app.services.site_service.site_type_fallback import (
    effective_site_type,
    load_site_types_by_period,
)
from app.services.user_service import user_to_profile_response

IDENTIFY_STEP_PERIOD = "period"
IDENTIFY_STEP_ROCK = "rock_type"
IDENTIFY_STEPS = (IDENTIFY_STEP_PERIOD, IDENTIFY_STEP_ROCK)

MESOZOIC_PERIODS: tuple[str, ...] = ("triassic", "jurassic", "cretaceous")

WRONG_MESSAGE = "That doesn't look quite right"


@dataclass(frozen=True)
class IdentifyOptionsResult:
    step: str
    choices: list[str]
    period_identified: bool
    rock_identified: bool
    identified: bool
    disabled_guesses: list[str]
    choice_images: dict[str, str]


@dataclass(frozen=True)
class IdentifyGuessResult:
    correct: bool
    step: str
    message: str | None
    disabled_guesses: list[str]
    xp_awarded: int
    period_identified: bool
    rock_identified: bool
    identified: bool
    site: SiteSummary
    profile: UserProfileResponse


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _discoverer_link(
    session: Session, *, user_id: int, site_id: int
) -> UserSite:
    link = session.exec(
        select(UserSite).where(
            col(UserSite.user_id) == user_id,
            col(UserSite.site_id) == site_id,
            col(UserSite.role) == USER_SITE_ROLE_DISCOVERER,
        )
    ).first()
    if link is None:
        raise ValidationError("Site must be discovered before identification")
    return link


def _has_identifier(
    session: Session, *, user_id: int, site_id: int
) -> bool:
    row = session.exec(
        select(UserSite.id).where(
            col(UserSite.user_id) == user_id,
            col(UserSite.site_id) == site_id,
            col(UserSite.role) == USER_SITE_ROLE_IDENTIFIER,
        )
    ).first()
    return row is not None


def _upsert_identifier(
    session: Session, *, user_id: int, site_id: int
) -> UserSite:
    existing = session.exec(
        select(UserSite).where(
            col(UserSite.user_id) == user_id,
            col(UserSite.site_id) == site_id,
            col(UserSite.role) == USER_SITE_ROLE_IDENTIFIER,
        )
    ).first()
    now = _utc_now()
    if existing is None:
        row = UserSite(
            user_id=user_id,
            site_id=site_id,
            role=USER_SITE_ROLE_IDENTIFIER,
            timestamp=now,
        )
        session.add(row)
        return row
    existing.timestamp = now
    session.add(existing)
    return existing


def _true_period_and_rock(
    session: Session, site: Site
) -> tuple[str, str]:
    types_by_period = load_site_types_by_period(session)
    site_type = session.get(SiteType, site.site_type_id) if site.site_type_id else None
    effective = effective_site_type(site, site_type, types_by_period)
    period = (
        (effective.period if effective is not None else None)
        or (site.period or "").strip().lower()
        or None
    )
    rock = (
        (effective.rock_type if effective is not None else None)
        or (site.rock_type or "").strip().lower()
        or None
    )
    if not period or not rock:
        raise ValidationError("Site is missing period or rock type")
    return period.lower(), rock.lower()


def _seeded_rng(*, user_id: int, site_id: int, salt: str) -> random.Random:
    digest = hashlib.sha256(
        f"{user_id}:{site_id}:{salt}".encode("utf-8")
    ).hexdigest()
    return random.Random(int(digest[:16], 16))


def _original_rock_image_url(*, period: str, rock_type: str) -> str | None:
    """Original-folder site-type image for period+rock, if present on disk/CDN."""
    from app.services.curated_image_service.resolve import (
        resolve_site_type_card_image_url,
    )
    from app.services.curated_image_service.versions import ORIGINAL_VERSION

    return resolve_site_type_card_image_url(
        period=period,
        rock_type=rock_type,
        version=ORIGINAL_VERSION,
    )


def _rock_image_url_for_choice(
    session: Session,
    *,
    period: str,
    rock_type: str,
) -> str | None:
    """Prefer Original image for the site's period; else any period for that rock."""
    direct = _original_rock_image_url(period=period, rock_type=rock_type)
    if direct:
        return direct
    rows = session.exec(
        select(SiteType.period).where(col(SiteType.rock_type) == rock_type)
    ).all()
    for other_period in rows:
        p = (other_period or "").strip().lower()
        if not p or p == period:
            continue
        url = _original_rock_image_url(period=p, rock_type=rock_type)
        if url:
            return url
    return None


def _rock_choices_for_period(
    session: Session,
    *,
    period: str,
    correct_rock: str,
    user_id: int,
    site_id: int,
    count: int = 6,
) -> tuple[list[str], dict[str, str]]:
    """Return ``count`` rock types (incl. correct) and Original image URLs."""
    from app.services.site_service.rules import ROCK_TYPES

    pool = sorted({(r or "").strip().lower() for r in ROCK_TYPES if r})
    if correct_rock not in pool:
        pool.append(correct_rock)

    others = [r for r in pool if r != correct_rock]
    with_image: list[str] = []
    without_image: list[str] = []
    for rock in others:
        if _rock_image_url_for_choice(session, period=period, rock_type=rock):
            with_image.append(rock)
        else:
            without_image.append(rock)

    rng = _seeded_rng(user_id=user_id, site_id=site_id, salt=f"rock:{period}")
    rng.shuffle(with_image)
    rng.shuffle(without_image)
    need = max(0, count - 1)
    picked = (with_image + without_image)[:need]
    choices = [correct_rock, *picked]
    rng.shuffle(choices)

    images: dict[str, str] = {}
    for rock in choices:
        url = _rock_image_url_for_choice(session, period=period, rock_type=rock)
        if url:
            images[rock] = url
    return choices, images


def get_identify_options(
    session: Session,
    *,
    site_id: int,
    user_id: int,
) -> IdentifyOptionsResult:
    site = session.get(Site, site_id)
    if site is None or site.data_source != DATA_SOURCE_FIELD:
        raise NotFoundError(f"Field site {site_id} not found")

    link = _discoverer_link(session, user_id=user_id, site_id=site_id)
    identified = bool(link.period_identified and link.rock_identified) or _has_identifier(
        session, user_id=user_id, site_id=site_id
    )
    period, rock = _true_period_and_rock(session, site)

    if not link.period_identified:
        return IdentifyOptionsResult(
            step=IDENTIFY_STEP_PERIOD,
            choices=list(MESOZOIC_PERIODS),
            period_identified=False,
            rock_identified=False,
            identified=identified,
            disabled_guesses=[],
            choice_images={},
        )

    choices, images = _rock_choices_for_period(
        session,
        period=period,
        correct_rock=rock,
        user_id=user_id,
        site_id=site_id,
    )
    return IdentifyOptionsResult(
        step=IDENTIFY_STEP_ROCK,
        choices=choices,
        period_identified=True,
        rock_identified=bool(link.rock_identified),
        identified=identified,
        disabled_guesses=[],
        choice_images=images,
    )


def _site_summary_for_user(
    session: Session, *, site_id: int, user: User
) -> SiteSummary:
    skill_level = level_for_xp(get_skill_xp(user, "site_stewardship"))
    row = get_site_by_id(
        session,
        site_id,
        data_source=DATA_SOURCE_FIELD,
        viewer_user_id=int(user.id),
    )
    types_by_period = load_site_types_by_period(session)
    return site_row_to_summary(
        row,
        types_by_period=types_by_period,
        stewardship_skill_level=skill_level,
    )


def submit_identify_guess(
    session: Session,
    *,
    site_id: int,
    user: User,
    step: str,
    guess: str,
) -> IdentifyGuessResult:
    normalized_step = (step or "").strip().lower()
    if normalized_step not in IDENTIFY_STEPS:
        raise ValidationError(
            f"step must be one of: {', '.join(IDENTIFY_STEPS)}"
        )
    normalized_guess = (guess or "").strip().lower()
    if not normalized_guess:
        raise ValidationError("guess is required")

    site = session.get(Site, site_id)
    if site is None or site.data_source != DATA_SOURCE_FIELD:
        raise NotFoundError(f"Field site {site_id} not found")

    user_id = int(user.id)
    link = _discoverer_link(session, user_id=user_id, site_id=site_id)
    period, rock = _true_period_and_rock(session, site)

    if normalized_step == IDENTIFY_STEP_PERIOD:
        if link.period_identified:
            raise ValidationError("Period already identified")
        correct_value = period
        wrongs = int(link.identify_period_wrongs or 0)
    else:
        if not link.period_identified:
            raise ValidationError("Identify the period first")
        if link.rock_identified:
            raise ValidationError("Rock type already identified")
        correct_value = rock
        wrongs = int(link.identify_rock_wrongs or 0)

    options = get_identify_options(session, site_id=site_id, user_id=user_id)
    if wrongs >= len(options.choices):
        raise ValidationError("No attempts remaining for this step")

    if normalized_guess not in {c.lower() for c in options.choices}:
        raise ValidationError("guess is not a valid option for this step")

    if normalized_guess != correct_value:
        if normalized_step == IDENTIFY_STEP_PERIOD:
            link.identify_period_wrongs = wrongs + 1
        else:
            link.identify_rock_wrongs = wrongs + 1
        session.add(link)
        session.commit()
        session.refresh(link)
        session.refresh(user)
        return IdentifyGuessResult(
            correct=False,
            step=normalized_step,
            message=WRONG_MESSAGE,
            disabled_guesses=[normalized_guess],
            xp_awarded=0,
            period_identified=bool(link.period_identified),
            rock_identified=bool(link.rock_identified),
            identified=False,
            site=_site_summary_for_user(session, site_id=site_id, user=user),
            profile=user_to_profile_response(session, user),
        )

    attempt = wrongs + 1
    xp = award_site_identification_xp(user, attempt=attempt)
    if normalized_step == IDENTIFY_STEP_PERIOD:
        link.period_identified = True
    else:
        link.rock_identified = True
    session.add(link)

    fully = bool(link.period_identified and link.rock_identified)
    if fully:
        _upsert_identifier(session, user_id=user_id, site_id=site_id)

    session.add(user)
    session.commit()
    session.refresh(user)
    session.refresh(link)

    # Re-enrich so redaction lifts after full identification.
    enriched_row = get_site_by_id(
        session,
        site_id,
        data_source=DATA_SOURCE_FIELD,
        viewer_user_id=user_id,
    )
    # Ensure identifier flag is visible even if enrich races.
    enriched = enrich_site_rows_for_viewer(
        session, [enriched_row], viewer_user_id=user_id
    )[0]
    skill_level = level_for_xp(get_skill_xp(user, "site_stewardship"))
    types_by_period = load_site_types_by_period(session)
    summary = site_row_to_summary(
        enriched,
        types_by_period=types_by_period,
        stewardship_skill_level=skill_level,
    )

    return IdentifyGuessResult(
        correct=True,
        step=normalized_step,
        message=None,
        disabled_guesses=[],
        xp_awarded=xp,
        period_identified=bool(link.period_identified),
        rock_identified=bool(link.rock_identified),
        identified=fully,
        site=summary,
        profile=user_to_profile_response(session, user),
    )
