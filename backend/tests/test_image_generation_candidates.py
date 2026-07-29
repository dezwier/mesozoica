"""Tests for image generation candidate selection and local file helpers."""

from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path

import pytest
from sqlmodel import Session

from app.models.dinosaur_type import DinosaurType
from app.models.fossil import Fossil
from app.services.dinosaur_image_generation_service.generate import _select_candidates as select_dino_candidates
from app.services.fossil_image_generation_service.generate import _select_candidates as select_fossil_candidates
from app.services.image_generation_service.local_files import (
    has_local_image,
    output_png_path,
    scan_existing_stems,
)


def _dinosaur(*, name: str, page_id: int, article: str = "<p>Article text here for testing.</p>") -> DinosaurType:
    return DinosaurType(
        name=name,
        wikipedia_page_id=page_id,
        wikipedia_title=name,
        cladogram={"genus": name},
        article=article,
        article_date=datetime(2026, 7, 8, tzinfo=timezone.utc),
    )


def test_scan_existing_stems_case_insensitive(tmp_path: Path):
    (tmp_path / "Tyrannosaurus.png").write_bytes(b"png")
    stems = scan_existing_stems(tmp_path, case_insensitive=True)
    assert "tyrannosaurus" in stems


def test_has_local_image_respects_existing_stems(tmp_path: Path):
    (tmp_path / "Allosaurus.jpg").write_bytes(b"jpg")
    stems = scan_existing_stems(tmp_path, case_insensitive=True)
    assert has_local_image(tmp_path, "allosaurus", existing_stems=stems, case_insensitive=True)
    assert not has_local_image(tmp_path, "Velociraptor", existing_stems=stems, case_insensitive=True)


def test_output_png_path_refuses_overwrite(tmp_path: Path):
    target = output_png_path(tmp_path, "Tyrannosaurus")
    target.write_bytes(b"existing")
    with pytest.raises(FileExistsError):
        from app.services.image_generation_service.postprocess import save_processed_png

        save_processed_png(b"fake", target)


def test_dinosaur_candidates_prioritize_fossil_count(session: Session, tmp_path: Path):
    low = _dinosaur(name="LowCount", page_id=1)
    high = _dinosaur(name="HighCount", page_id=2)
    session.add(low)
    session.add(high)
    session.commit()
    session.refresh(low)
    session.refresh(high)

    session.add(Fossil(id=101, dinosaur_id=high.id, pres_mode="body"))
    session.add(Fossil(id=102, dinosaur_id=high.id, pres_mode="body"))
    session.add(Fossil(id=103, dinosaur_id=low.id, pres_mode="body"))
    session.commit()

    candidates, skipped_existing = select_dino_candidates(
        session,
        output_dir=tmp_path,
        existing_stems=set(),
    )
    assert skipped_existing == 0
    assert [item.dinosaur.name for item in candidates[:2]] == ["HighCount", "LowCount"]
    assert candidates[0].fossil_count == 2
    assert candidates[1].fossil_count == 1


def test_dinosaur_candidates_skip_existing_image(session: Session, tmp_path: Path):
    dino = _dinosaur(name="ExistingDino", page_id=10)
    session.add(dino)
    session.commit()
    (tmp_path / "ExistingDino.png").write_bytes(b"png")
    existing = scan_existing_stems(tmp_path, case_insensitive=True)

    candidates, skipped_existing = select_dino_candidates(
        session,
        output_dir=tmp_path,
        existing_stems=existing,
    )
    assert skipped_existing == 1
    assert candidates == []


def test_fossil_candidates_prioritize_dinos_with_images(session: Session, tmp_path: Path):
    dino_with = _dinosaur(name="WithImage", page_id=20)
    dino_without = _dinosaur(name="WithoutImage", page_id=21)
    session.add(dino_with)
    session.add(dino_without)
    session.commit()
    session.refresh(dino_with)
    session.refresh(dino_without)

    fossil_a = Fossil(id=201, dinosaur_id=dino_without.id, pres_mode="body", llm_enriched=True)
    fossil_b = Fossil(id=202, dinosaur_id=dino_with.id, pres_mode="body", llm_enriched=True)
    session.add(fossil_a)
    session.add(fossil_b)
    session.commit()

    dino_dir = tmp_path / "dinos"
    fossil_dir = tmp_path / "fossils"
    dino_dir.mkdir()
    fossil_dir.mkdir()
    (dino_dir / "WithImage.png").write_bytes(b"png")
    dinosaur_stems = scan_existing_stems(dino_dir, case_insensitive=True)

    candidates, skipped_existing = select_fossil_candidates(
        session,
        output_dir=fossil_dir,
        existing_stems=set(),
        dinosaur_image_stems=dinosaur_stems,
    )
    assert skipped_existing == 0
    assert len(candidates) == 2
    assert candidates[0].fossil.id == 202
    assert candidates[0].dinosaur_has_image is True
    assert candidates[1].fossil.id == 201
    assert candidates[1].dinosaur_has_image is False


def test_fossil_candidates_skip_not_llm_enriched(session: Session, tmp_path: Path):
    dino = _dinosaur(name="EnrichedOnly", page_id=30)
    session.add(dino)
    session.commit()
    session.refresh(dino)

    enriched = Fossil(id=301, dinosaur_id=dino.id, pres_mode="body", llm_enriched=True)
    pending = Fossil(id=302, dinosaur_id=dino.id, pres_mode="body", llm_enriched=False)
    session.add(enriched)
    session.add(pending)
    session.commit()

    fossil_dir = tmp_path / "fossils"
    fossil_dir.mkdir()

    candidates, skipped_existing = select_fossil_candidates(
        session,
        output_dir=fossil_dir,
        existing_stems=set(),
        dinosaur_image_stems=set(),
    )
    assert skipped_existing == 0
    assert len(candidates) == 1
    assert candidates[0].fossil.id == 301
