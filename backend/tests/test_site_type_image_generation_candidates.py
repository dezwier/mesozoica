"""Tests for site-type image generation candidate selection."""

from __future__ import annotations

from pathlib import Path

from sqlmodel import Session

from app.models.site import Site
from app.models.site_type import SiteType
from app.services.site_type_image_generation_service.generate import _select_candidates


def _site_type(*, period: str, rock_type: str) -> SiteType:
    return SiteType(period=period, rock_type=rock_type)


def test_site_type_candidates_skip_existing_image(session: Session, tmp_path: Path):
    row = _site_type(period="cretaceous", rock_type="sandstone")
    session.add(row)
    session.commit()
    session.refresh(row)
    assert row.id is not None

    (tmp_path / f"{row.id}.png").write_bytes(b"png")
    existing = {str(row.id)}

    candidates, skipped_existing = _select_candidates(
        session,
        output_dir=tmp_path,
        existing_stems=existing,
    )
    assert skipped_existing == 1
    assert candidates == []


def test_site_type_candidates_respect_site_type_ids_filter(
    session: Session, tmp_path: Path
):
    first = _site_type(period="jurassic", rock_type="claystone")
    second = _site_type(period="cretaceous", rock_type="sandstone")
    session.add(first)
    session.add(second)
    session.commit()
    session.refresh(first)
    session.refresh(second)
    assert first.id is not None
    assert second.id is not None

    candidates, skipped_existing = _select_candidates(
        session,
        output_dir=tmp_path,
        existing_stems=set(),
        site_type_ids=[second.id],
    )
    assert skipped_existing == 0
    assert len(candidates) == 1
    assert candidates[0].site_type.id == second.id


def test_site_type_candidates_prioritize_by_site_count(session: Session, tmp_path: Path):
    popular = _site_type(period="cretaceous", rock_type="sandstone")
    rare = _site_type(period="jurassic", rock_type="claystone")
    session.add(popular)
    session.add(rare)
    session.commit()
    session.refresh(popular)
    session.refresh(rare)
    assert popular.id is not None
    assert rare.id is not None

    for site_id in range(100, 103):
        session.add(Site(site_id=site_id, site_type_id=popular.id))
    session.add(Site(site_id=200, site_type_id=rare.id))
    session.commit()

    candidates, skipped_existing = _select_candidates(
        session,
        output_dir=tmp_path,
        existing_stems=set(),
    )
    assert skipped_existing == 0
    assert len(candidates) == 2
    assert candidates[0].site_type.id == popular.id
    assert candidates[0].site_count == 3
    assert candidates[1].site_type.id == rare.id
    assert candidates[1].site_count == 1


def test_site_type_candidates_include_all_missing_by_default(
    session: Session, tmp_path: Path
):
    session.add(_site_type(period="triassic", rock_type="mudstone"))
    session.add(_site_type(period="jurassic", rock_type="limestone"))
    session.commit()

    candidates, skipped_existing = _select_candidates(
        session,
        output_dir=tmp_path,
        existing_stems=set(),
    )
    assert skipped_existing == 0
    assert len(candidates) == 2
