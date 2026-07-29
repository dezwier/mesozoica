"""Related fossils and dinosaurs for a site."""

from __future__ import annotations

import hashlib

from sqlmodel import Session, col, select

from app.core.exceptions import NotFoundError
from app.models.data_source import DATA_SOURCE_FIELD
from app.models.dinosaur_type import DinosaurType
from app.models.fossil import Fossil
from app.models.site import Site
from app.models.user_fossil import (
    FOSSIL_STATUS_DISCOVERED,
    FOSSIL_STATUS_HIDDEN,
    USER_FOSSIL_ROLE_DISCOVERER,
    UserFossil,
)
from app.schemas.site import SiteDinosaurThumb, SiteDinoFossilGroup, SiteFossilThumb


def _ensure_site_exists(session: Session, site_id: int) -> Site:
    row = session.get(Site, site_id)
    if row is None:
        raise NotFoundError(f"Site {site_id} not found")
    return row


def _discovered_fossil_ids_for_user(
    session: Session,
    *,
    site_id: int,
    user_id: int,
) -> set[int]:
    rows = session.exec(
        select(UserFossil.fossil_id)
        .join(Fossil, col(Fossil.id) == col(UserFossil.fossil_id))
        .where(
            col(UserFossil.user_id) == user_id,
            col(UserFossil.role) == USER_FOSSIL_ROLE_DISCOVERER,
            col(Fossil.site_id) == site_id,
            col(Fossil.data_source) == DATA_SOURCE_FIELD,
        )
    ).all()
    return {int(fid) for fid in rows}


def _should_filter_field_fossils(
    site: Site,
    *,
    is_admin: bool,
) -> bool:
    """Non-admins only see field fossils they have discovered.

    Admins still see all on site/dino cards (with status for dimming).
    """
    return site.data_source == DATA_SOURCE_FIELD and not is_admin


def _thumb(
    *,
    fossil_id: int,
    main_image_url: str | None,
    identified_name: str | None,
    discovered_ids: set[int] | None,
) -> SiteFossilThumb:
    if discovered_ids is None:
        # Archive (or no viewer): no discovery gate — show at full opacity.
        status = FOSSIL_STATUS_DISCOVERED
    elif int(fossil_id) in discovered_ids:
        status = FOSSIL_STATUS_DISCOVERED
    else:
        status = FOSSIL_STATUS_HIDDEN
    return SiteFossilThumb(
        id=fossil_id,
        main_image_url=main_image_url,
        identified_name=identified_name,
        status=status,
    )


def list_site_fossils(
    session: Session,
    site_id: int,
    *,
    viewer_user_id: int | None = None,
    is_admin: bool = False,
) -> list[SiteFossilThumb]:
    site = _ensure_site_exists(session, site_id)
    rows = session.exec(
        select(Fossil.id, Fossil.main_image_url, Fossil.identified_name).where(
            col(Fossil.site_id) == site_id,
            col(Fossil.data_source) == site.data_source,
        )
    ).all()
    discovered: set[int] | None = None
    if site.data_source == DATA_SOURCE_FIELD and viewer_user_id is not None:
        discovered = _discovered_fossil_ids_for_user(
            session, site_id=site_id, user_id=viewer_user_id
        )
    if _should_filter_field_fossils(site, is_admin=is_admin):
        if viewer_user_id is None or discovered is None:
            rows = []
        else:
            rows = [row for row in rows if int(row[0]) in discovered]
    rows = sorted(
        rows,
        key=lambda row: hashlib.md5(f"{row[0]}{site_id}".encode()).hexdigest(),
    )
    return [
        _thumb(
            fossil_id=fossil_id,
            main_image_url=main_image_url,
            identified_name=identified_name,
            discovered_ids=discovered,
        )
        for fossil_id, main_image_url, identified_name in rows
    ]


def list_site_dinosaurs(
    session: Session,
    site_id: int,
    *,
    viewer_user_id: int | None = None,
    is_admin: bool = False,
) -> list[SiteDinosaurThumb]:
    site = _ensure_site_exists(session, site_id)
    stmt = (
        select(DinosaurType.id, DinosaurType.name, DinosaurType.main_image_url)
        .join(Fossil, col(Fossil.dinosaur_id) == col(DinosaurType.id))
        .where(
            col(Fossil.site_id) == site_id,
            col(Fossil.data_source) == site.data_source,
        )
    )
    if _should_filter_field_fossils(site, is_admin=is_admin):
        if viewer_user_id is None:
            return []
        stmt = stmt.join(
            UserFossil,
            (col(UserFossil.fossil_id) == col(Fossil.id))
            & (col(UserFossil.user_id) == viewer_user_id)
            & (col(UserFossil.role) == USER_FOSSIL_ROLE_DISCOVERER),
        )
    rows = session.exec(
        stmt.distinct().order_by(DinosaurType.name, DinosaurType.id)
    ).all()
    return [
        SiteDinosaurThumb(id=dino_id, name=name, main_image_url=main_image_url)
        for dino_id, name, main_image_url in rows
    ]


def list_site_dino_fossil_groups(
    session: Session,
    site_id: int,
    *,
    viewer_user_id: int | None = None,
    is_admin: bool = False,
) -> list[SiteDinoFossilGroup]:
    site = _ensure_site_exists(session, site_id)
    stmt = (
        select(
            DinosaurType.id,
            DinosaurType.name,
            DinosaurType.main_image_url,
            Fossil.id,
            Fossil.main_image_url,
            Fossil.identified_name,
        )
        .join(Fossil, col(Fossil.dinosaur_id) == col(DinosaurType.id))
        .where(
            col(Fossil.site_id) == site_id,
            col(Fossil.data_source) == site.data_source,
        )
    )
    discovered: set[int] | None = None
    if site.data_source == DATA_SOURCE_FIELD and viewer_user_id is not None:
        discovered = _discovered_fossil_ids_for_user(
            session, site_id=site_id, user_id=viewer_user_id
        )
    if _should_filter_field_fossils(site, is_admin=is_admin):
        if viewer_user_id is None:
            return []
        stmt = stmt.join(
            UserFossil,
            (col(UserFossil.fossil_id) == col(Fossil.id))
            & (col(UserFossil.user_id) == viewer_user_id)
            & (col(UserFossil.role) == USER_FOSSIL_ROLE_DISCOVERER),
        )
    rows = session.exec(
        stmt.order_by(DinosaurType.name, DinosaurType.id, Fossil.id)
    ).all()

    groups: list[SiteDinoFossilGroup] = []
    current_dino_id: int | None = None
    current_group: SiteDinoFossilGroup | None = None

    for dino_id, name, dino_image, fossil_id, fossil_image, identified_name in rows:
        if dino_id != current_dino_id:
            if current_group is not None:
                groups.append(current_group)
            current_dino_id = dino_id
            current_group = SiteDinoFossilGroup(
                dinosaur=SiteDinosaurThumb(
                    id=dino_id,
                    name=name,
                    main_image_url=dino_image,
                ),
                fossils=[],
            )
        assert current_group is not None
        current_group.fossils.append(
            _thumb(
                fossil_id=fossil_id,
                main_image_url=fossil_image,
                identified_name=identified_name,
                discovered_ids=discovered,
            )
        )

    if current_group is not None:
        groups.append(current_group)

    return groups
