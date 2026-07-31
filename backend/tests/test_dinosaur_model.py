"""Tests for DinosaurType / DinosaurTypeRevision SQLModel."""

from datetime import datetime, timezone

from sqlmodel import Session, select

from app.models.dinosaur_type import DinosaurType
from tests.helpers.dinosaur_fixtures import current_revision, seed_dinosaur_type


def test_dinosaur_roundtrip():
    from app.core.database import engine

    with Session(engine) as session:
        row = seed_dinosaur_type(
            session,
            name="Tyrannosaurus",
            wikipedia_page_id=30467,
            birth=77.0,
            death=66.0,
            period="Late Cretaceous",
            cladogram={"kingdom": "Animalia", "genus": "Tyrannosaurus"},
            diet_type="carnivore",
            short_description=(
                "A towering Late Cretaceous apex predator with a bone-crushing bite."
            ),
            long_description="Tyrannosaurus is a genus of large theropod dinosaur.",
            article="<p>html</p>",
            article_date=datetime(2026, 7, 8, tzinfo=timezone.utc),
            length="12 m",
            mass="7 t",
            location="North America",
            llm_enriched=True,
        )

        loaded = session.exec(
            select(DinosaurType).where(DinosaurType.wikipedia_page_id == 30467)
        ).first()
        revision = current_revision(session, loaded)

    assert loaded is not None
    assert loaded.name == "Tyrannosaurus"
    assert loaded.insert_date is not None
    assert revision is not None
    assert revision.cladogram["genus"] == "Tyrannosaurus"
    assert revision.length == "12 m"
    assert revision.mass == "7 t"
    assert revision.location == "North America"
    assert revision.llm_enriched is True
