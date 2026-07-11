"""Tests for Dinosaur SQLModel."""

from datetime import datetime, timezone

from sqlmodel import Session, select

from app.models.dinosaur import Dinosaur


def test_dinosaur_roundtrip():
    row = Dinosaur(
        name="Tyrannosaurus",
        wikipedia_page_id=30467,
        wikipedia_title="Tyrannosaurus",
        birth=77.0,
        death=66.0,
        period="Late Cretaceous",
        cladogram={"kingdom": "Animalia", "genus": "Tyrannosaurus"},
        diet_type="carnivore",
        short_description="Genus of Late Cretaceous theropod",
        long_description="Tyrannosaurus is a genus of large theropod dinosaur.",
        article="<p>html</p>",
        article_date=datetime(2026, 7, 8, tzinfo=timezone.utc),
    )

    from app.core.database import engine

    with Session(engine) as session:
        session.add(row)
        session.commit()
        session.refresh(row)

        loaded = session.exec(
            select(Dinosaur).where(Dinosaur.wikipedia_page_id == 30467)
        ).first()

    assert loaded is not None
    assert loaded.name == "Tyrannosaurus"
    assert loaded.cladogram["genus"] == "Tyrannosaurus"
    assert loaded.insert_date is not None
