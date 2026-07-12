"""Fossil occurrence records synced from the Paleobiology Database."""

from __future__ import annotations

from decimal import Decimal
from typing import Optional

from sqlalchemy import Column, ForeignKey, Numeric, Text
from sqlmodel import Field, SQLModel


class Fossil(SQLModel, table=True):
    """PBDB fossil occurrence linked to a dinosaur genus."""

    __tablename__ = "fossil"

    id: int = Field(primary_key=True, description="PBDB occurrence_no")
    dinosaur_id: int = Field(
        sa_column=Column(
            "dinosaur_id",
            ForeignKey("dinosaur.id", ondelete="CASCADE"),
            nullable=False,
            index=True,
        ),
    )

    # Taxonomy
    identified_name: Optional[str] = Field(default=None, max_length=255)
    identified_rank: Optional[str] = Field(default=None, max_length=50)
    accepted_name: Optional[str] = Field(default=None, max_length=255)
    accepted_no: Optional[int] = Field(default=None)
    accepted_rank: Optional[str] = Field(default=None, max_length=50)
    accepted_attr: Optional[str] = Field(default=None, max_length=255)
    genus: Optional[str] = Field(default=None, max_length=100)
    family: Optional[str] = Field(default=None, max_length=100)
    taxon_order: Optional[str] = Field(default=None, max_length=100)
    taxon_class: Optional[str] = Field(default=None, max_length=100)
    phylum: Optional[str] = Field(default=None, max_length=100)

    # Geography
    latitude: Optional[Decimal] = Field(default=None, sa_column=Column(Numeric(9, 6)))
    longitude: Optional[Decimal] = Field(default=None, sa_column=Column(Numeric(9, 6)))
    country_code: Optional[str] = Field(default=None, max_length=2)
    state: Optional[str] = Field(default=None, max_length=100)
    geogcomments: Optional[str] = Field(default=None, sa_column=Column(Text))
    geogscale: Optional[str] = Field(default=None, max_length=100)
    geoplate: Optional[int] = Field(default=None)
    latlng_basis: Optional[str] = Field(default=None, max_length=100)
    latlng_precision: Optional[int] = Field(default=None)
    paleolat: Optional[Decimal] = Field(default=None, sa_column=Column(Numeric(9, 6)))
    paleolng: Optional[Decimal] = Field(default=None, sa_column=Column(Numeric(9, 6)))
    paleomodel: Optional[str] = Field(default=None, max_length=50)
    paleoage: Optional[str] = Field(default=None, max_length=50)

    # Stratigraphy
    geological_formation: Optional[str] = Field(default=None, max_length=255)
    min_age_ma: Optional[Decimal] = Field(default=None, sa_column=Column(Numeric(5, 2)))
    max_age_ma: Optional[Decimal] = Field(default=None, sa_column=Column(Numeric(5, 2)))
    early_interval: Optional[str] = Field(default=None, max_length=100)
    stratcomments: Optional[str] = Field(default=None, sa_column=Column(Text))
    stratscale: Optional[str] = Field(default=None, max_length=100)
    lithdescript: Optional[str] = Field(default=None, max_length=500)
    lithology1: Optional[str] = Field(default=None, max_length=100)
    lithadj1: Optional[str] = Field(default=None, max_length=100)
    concentration: Optional[str] = Field(default=None, max_length=100)
    temporal_resolution: Optional[str] = Field(default=None, max_length=100)

    # Collection
    collection_name: Optional[str] = Field(default=None, max_length=255)
    collection_aka: Optional[str] = Field(default=None, max_length=255)
    collection_no: Optional[int] = Field(default=None)
    collection_dates: Optional[str] = Field(default=None, max_length=100)
    collection_type: Optional[str] = Field(default=None, max_length=50)
    collection_methods: Optional[str] = Field(default=None, sa_column=Column(Text))
    collectors: Optional[str] = Field(default=None, max_length=500)
    museum: Optional[str] = Field(default=None, max_length=100)
    research_group: Optional[str] = Field(default=None, max_length=100)

    # Occurrence detail
    occurrence_comments: Optional[str] = Field(default=None, sa_column=Column(Text))
    composition: Optional[str] = Field(default=None, max_length=100)
    architecture: Optional[str] = Field(default=None, max_length=100)
    fragmentation: Optional[str] = Field(default=None, max_length=100)
    pres_mode: Optional[str] = Field(default=None, max_length=100)
    preservation_quality: Optional[str] = Field(default=None, max_length=50)
    abund_value: Optional[int] = Field(default=None)
    abund_unit: Optional[str] = Field(default=None, max_length=50)
    fossilsfrom1: Optional[str] = Field(default=None, max_length=10)
    size_classes: Optional[str] = Field(default=None, max_length=100)
    record_type: Optional[str] = Field(default=None, max_length=20)

    # Ecology
    diet: Optional[str] = Field(default=None, max_length=100)
    environment: Optional[str] = Field(default=None, max_length=255)
    taxon_environment: Optional[str] = Field(default=None, max_length=100)
    life_habit: Optional[str] = Field(default=None, max_length=255)
    motility: Optional[str] = Field(default=None, max_length=100)
    reproduction: Optional[str] = Field(default=None, max_length=255)
    ontogeny: Optional[str] = Field(default=None, max_length=255)

    # Reference
    reference_no: Optional[int] = Field(default=None)
    ref_author: Optional[str] = Field(default=None, max_length=255)
    ref_pubyr: Optional[int] = Field(default=None)
    reid_no: Optional[int] = Field(default=None)

    # Legacy composed narrative (no longer populated on sync)
    description: Optional[str] = Field(default=None, sa_column=Column(Text))
    main_image_url: Optional[str] = Field(default=None, max_length=2048)
