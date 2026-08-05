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
    FOSSIL_STATUS_IN_SITU,
    UserFossil,
    role_to_status,
)
from app.models.user_site import USER_SITE_ROLE_DISCOVERER, UserSite
from app.schemas.site import SiteDinosaurThumb, SiteDinoFossilGroup, SiteFossilThumb


def _ensure_site_exists(session: Session, site_id: int) -> Site:
    row = session.get(Site, site_id)
    if row is None:
        raise NotFoundError(f"Site {site_id} not found")
    return row


def _linked_fossil_ids_for_user(
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
            col(Fossil.site_id) == site_id,
            col(Fossil.data_source) == DATA_SOURCE_FIELD,
        )
    ).all()
    return {int(fid) for fid in rows}


def _viewer_is_site_discoverer(
    session: Session,
    *,
    site_id: int,
    user_id: int,
) -> bool:
    row = session.exec(
        select(UserSite.id).where(
            col(UserSite.user_id) == user_id,
            col(UserSite.site_id) == site_id,
            col(UserSite.role) == USER_SITE_ROLE_DISCOVERER,
        )
    ).first()
    return row is not None


def _fossil_status_for_viewer(
    session: Session,
    *,
    fossil_id: int,
    user_id: int,
    depth_cm: int | None,
    is_discoverer: bool,
    linked: set[int],
) -> str:
    if fossil_id in linked:
        link = session.exec(
            select(UserFossil)
            .where(
                col(UserFossil.user_id) == user_id,
                col(UserFossil.fossil_id) == fossil_id,
            )
            .order_by(col(UserFossil.timestamp).desc())
        ).first()
        return role_to_status(link.role if link is not None else None)
    if is_discoverer and depth_cm == 0:
        return FOSSIL_STATUS_IN_SITU
    return FOSSIL_STATUS_HIDDEN


def _should_filter_field_fossils(
    site: Site,
    *,
    include_hidden: bool,
) -> bool:
    """Without include_hidden, only visible in-situ / linked fossils are returned.

    Admins must pass include_hidden=true for the card admin peek (faded thumbs).
    """
    return site.data_source == DATA_SOURCE_FIELD and not include_hidden


def _visible_field_fossil_ids(
    *,
    fossil_id: int,
    depth_cm: int | None,
    linked: set[int],
    is_discoverer: bool,
) -> bool:
    """Surface (depth 0) fossils are visible to site discoverers without user_fossil."""
    if fossil_id in linked:
        return True
    return is_discoverer and depth_cm == 0


def _thumb(
    *,
    fossil_id: int,
    main_image_url: str | None,
    identified_name: str | None,
    status: str,
) -> SiteFossilThumb:
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
    include_hidden: bool = False,
) -> list[SiteFossilThumb]:
    site = _ensure_site_exists(session, site_id)
    rows = session.exec(
        select(
            Fossil.id,
            Fossil.main_image_url,
            Fossil.identified_name,
            Fossil.depth_cm,
        ).where(
            col(Fossil.site_id) == site_id,
            col(Fossil.data_source) == site.data_source,
        )
    ).all()
    linked: set[int] = set()
    is_discoverer = False
    if site.data_source == DATA_SOURCE_FIELD and viewer_user_id is not None:
        linked = _linked_fossil_ids_for_user(
            session, site_id=site_id, user_id=viewer_user_id
        )
        is_discoverer = _viewer_is_site_discoverer(
            session, site_id=site_id, user_id=viewer_user_id
        )
    if _should_filter_field_fossils(site, include_hidden=include_hidden):
        if viewer_user_id is None:
            rows = []
        else:
            rows = [
                row
                for row in rows
                if _visible_field_fossil_ids(
                    fossil_id=int(row[0]),
                    depth_cm=row[3],
                    linked=linked,
                    is_discoverer=is_discoverer,
                )
            ]
    rows = sorted(
        rows,
        key=lambda row: hashlib.md5(f"{row[0]}{site_id}".encode()).hexdigest(),
    )
    result: list[SiteFossilThumb] = []
    for fossil_id, main_image_url, identified_name, depth_cm in rows:
        if site.data_source != DATA_SOURCE_FIELD or viewer_user_id is None:
            status = FOSSIL_STATUS_DISCOVERED
        else:
            status = _fossil_status_for_viewer(
                session,
                fossil_id=int(fossil_id),
                user_id=viewer_user_id,
                depth_cm=depth_cm,
                is_discoverer=is_discoverer,
                linked=linked,
            )
        result.append(
            _thumb(
                fossil_id=fossil_id,
                main_image_url=main_image_url,
                identified_name=identified_name,
                status=status,
            )
        )
    return result


def list_site_dinosaurs(
    session: Session,
    site_id: int,
    *,
    viewer_user_id: int | None = None,
    include_hidden: bool = False,
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
    if _should_filter_field_fossils(site, include_hidden=include_hidden):
        if viewer_user_id is None:
            return []
        linked = _linked_fossil_ids_for_user(
            session, site_id=site_id, user_id=viewer_user_id
        )
        is_discoverer = _viewer_is_site_discoverer(
            session, site_id=site_id, user_id=viewer_user_id
        )
        fossil_rows = session.exec(
            select(Fossil.id, Fossil.depth_cm).where(
                col(Fossil.site_id) == site_id,
                col(Fossil.data_source) == site.data_source,
            )
        ).all()
        visible_ids = [
            int(fid)
            for fid, depth_cm in fossil_rows
            if _visible_field_fossil_ids(
                fossil_id=int(fid),
                depth_cm=depth_cm,
                linked=linked,
                is_discoverer=is_discoverer,
            )
        ]
        if not visible_ids:
            return []
        stmt = stmt.where(col(Fossil.id).in_(visible_ids))
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
    include_hidden: bool = False,
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
            Fossil.depth_cm,
        )
        .join(Fossil, col(Fossil.dinosaur_id) == col(DinosaurType.id))
        .where(
            col(Fossil.site_id) == site_id,
            col(Fossil.data_source) == site.data_source,
        )
    )
    linked: set[int] = set()
    is_discoverer = False
    if site.data_source == DATA_SOURCE_FIELD and viewer_user_id is not None:
        linked = _linked_fossil_ids_for_user(
            session, site_id=site_id, user_id=viewer_user_id
        )
        is_discoverer = _viewer_is_site_discoverer(
            session, site_id=site_id, user_id=viewer_user_id
        )
    if _should_filter_field_fossils(site, include_hidden=include_hidden):
        if viewer_user_id is None:
            return []
        fossil_rows = session.exec(
            select(Fossil.id, Fossil.depth_cm).where(
                col(Fossil.site_id) == site_id,
                col(Fossil.data_source) == site.data_source,
            )
        ).all()
        visible_ids = [
            int(fid)
            for fid, depth_cm in fossil_rows
            if _visible_field_fossil_ids(
                fossil_id=int(fid),
                depth_cm=depth_cm,
                linked=linked,
                is_discoverer=is_discoverer,
            )
        ]
        if not visible_ids:
            return []
        stmt = stmt.where(col(Fossil.id).in_(visible_ids))
    rows = session.exec(
        stmt.order_by(DinosaurType.name, DinosaurType.id, Fossil.id)
    ).all()

    groups: list[SiteDinoFossilGroup] = []
    current_dino_id: int | None = None
    current_group: SiteDinoFossilGroup | None = None

    for (
        dino_id,
        name,
        dino_image,
        fossil_id,
        fossil_image,
        identified_name,
        depth_cm,
    ) in rows:
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
        if site.data_source != DATA_SOURCE_FIELD or viewer_user_id is None:
            status = FOSSIL_STATUS_DISCOVERED
        else:
            status = _fossil_status_for_viewer(
                session,
                fossil_id=int(fossil_id),
                user_id=viewer_user_id,
                depth_cm=depth_cm,
                is_discoverer=is_discoverer,
                linked=linked,
            )
        current_group.fossils.append(
            _thumb(
                fossil_id=fossil_id,
                main_image_url=fossil_image,
                identified_name=identified_name,
                status=status,
            )
        )

    if current_group is not None:
        groups.append(current_group)

    return groups
