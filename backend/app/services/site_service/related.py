"""Related fossils and dinosaurs for a site."""

from __future__ import annotations

from sqlmodel import Session, col, select

from app.core.exceptions import NotFoundError
from app.models.dinosaur import Dinosaur
from app.models.fossil import Fossil
from app.models.fossil_clean import FossilClean
from app.models.site_clean import SiteClean
from app.schemas.site import SiteDinosaurThumb, SiteDinoFossilGroup, SiteFossilThumb


def _ensure_site_exists(session: Session, site_id: int) -> None:
    row = session.get(SiteClean, site_id)
    if row is None:
        raise NotFoundError(f"Site {site_id} not found")


def list_site_fossils(session: Session, site_id: int) -> list[SiteFossilThumb]:
    _ensure_site_exists(session, site_id)
    rows = session.exec(
        select(Fossil.id, Fossil.main_image_url)
        .join(FossilClean, col(FossilClean.fossil_id) == col(Fossil.id))
        .where(col(FossilClean.site_id) == site_id)
        .order_by(Fossil.id)
    ).all()
    return [
        SiteFossilThumb(id=fossil_id, main_image_url=main_image_url)
        for fossil_id, main_image_url in rows
    ]


def list_site_dinosaurs(session: Session, site_id: int) -> list[SiteDinosaurThumb]:
    _ensure_site_exists(session, site_id)
    rows = session.exec(
        select(Dinosaur.id, Dinosaur.name, Dinosaur.main_image_url)
        .join(FossilClean, col(FossilClean.dinosaur_id) == col(Dinosaur.id))
        .where(col(FossilClean.site_id) == site_id)
        .distinct()
        .order_by(Dinosaur.name, Dinosaur.id)
    ).all()
    return [
        SiteDinosaurThumb(id=dino_id, name=name, main_image_url=main_image_url)
        for dino_id, name, main_image_url in rows
    ]


def list_site_dino_fossil_groups(
    session: Session, site_id: int
) -> list[SiteDinoFossilGroup]:
    _ensure_site_exists(session, site_id)
    rows = session.exec(
        select(
            Dinosaur.id,
            Dinosaur.name,
            Dinosaur.main_image_url,
            Fossil.id,
            Fossil.main_image_url,
        )
        .join(FossilClean, col(FossilClean.dinosaur_id) == col(Dinosaur.id))
        .join(Fossil, col(FossilClean.fossil_id) == col(Fossil.id))
        .where(col(FossilClean.site_id) == site_id)
        .order_by(Dinosaur.name, Dinosaur.id, Fossil.id)
    ).all()

    groups: list[SiteDinoFossilGroup] = []
    current_dino_id: int | None = None
    current_group: SiteDinoFossilGroup | None = None

    for dino_id, name, dino_image, fossil_id, fossil_image in rows:
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
            SiteFossilThumb(id=fossil_id, main_image_url=fossil_image)
        )

    if current_group is not None:
        groups.append(current_group)

    return groups
