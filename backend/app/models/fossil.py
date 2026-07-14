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
    identified_no: Optional[int] = Field(default=None)
    identified_rank: Optional[str] = Field(default=None, max_length=50)
    taxon_difference: Optional[str] = Field(default=None, max_length=100)
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
    county: Optional[str] = Field(default=None, max_length=100)
    altitude_value: Optional[Decimal] = Field(default=None, sa_column=Column(Numeric(9, 2)))
    altitude_unit: Optional[str] = Field(default=None, max_length=50)
    protected: Optional[str] = Field(default=None, max_length=20)
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
    geological_group: Optional[str] = Field(default=None, max_length=255)
    geological_member: Optional[str] = Field(default=None, max_length=255)
    strat_zone: Optional[str] = Field(default=None, max_length=100)
    localsection: Optional[str] = Field(default=None, max_length=255)
    localbed: Optional[str] = Field(default=None, max_length=255)
    localbedunit: Optional[str] = Field(default=None, max_length=100)
    localorder: Optional[str] = Field(default=None, max_length=50)
    regionalsection: Optional[str] = Field(default=None, max_length=255)
    regionalbed: Optional[str] = Field(default=None, max_length=255)
    regionalbedunit: Optional[str] = Field(default=None, max_length=100)
    regionalorder: Optional[str] = Field(default=None, max_length=50)
    min_age_ma: Optional[Decimal] = Field(default=None, sa_column=Column(Numeric(5, 2)))
    max_age_ma: Optional[Decimal] = Field(default=None, sa_column=Column(Numeric(5, 2)))
    early_interval: Optional[str] = Field(default=None, max_length=100)
    late_interval: Optional[str] = Field(default=None, max_length=100)
    stratcomments: Optional[str] = Field(default=None, sa_column=Column(Text))
    stratscale: Optional[str] = Field(default=None, max_length=100)
    lithdescript: Optional[str] = Field(default=None, max_length=500)
    lithology1: Optional[str] = Field(default=None, max_length=100)
    lithadj1: Optional[str] = Field(default=None, max_length=100)
    lithification1: Optional[str] = Field(default=None, max_length=100)
    minor_lithology1: Optional[str] = Field(default=None, max_length=100)
    lithology2: Optional[str] = Field(default=None, max_length=100)
    lithadj2: Optional[str] = Field(default=None, max_length=100)
    lithification2: Optional[str] = Field(default=None, max_length=100)
    minor_lithology2: Optional[str] = Field(default=None, max_length=100)
    fossilsfrom2: Optional[str] = Field(default=None, max_length=10)
    concentration: Optional[str] = Field(default=None, max_length=100)
    temporal_resolution: Optional[str] = Field(default=None, max_length=100)

    site_id: Optional[int] = Field(
        default=None,
        sa_column=Column(
            "site_id",
            ForeignKey("site.site_id", ondelete="SET NULL"),
            nullable=True,
            index=True,
        ),
        description="PBDB collection_no; set by site_sync",
    )

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
    collection_coverage: Optional[str] = Field(default=None, max_length=100)
    collection_size: Optional[str] = Field(default=None, max_length=100)
    rock_censused: Optional[str] = Field(default=None, max_length=255)
    collection_comments: Optional[str] = Field(default=None, sa_column=Column(Text))
    taxonomy_comments: Optional[str] = Field(default=None, sa_column=Column(Text))

    # Occurrence detail
    occurrence_comments: Optional[str] = Field(default=None, sa_column=Column(Text))
    composition: Optional[str] = Field(default=None, max_length=100)
    architecture: Optional[str] = Field(default=None, max_length=100)
    thickness: Optional[str] = Field(default=None, max_length=100)
    reinforcement: Optional[str] = Field(default=None, max_length=100)
    plant_organ: Optional[str] = Field(default=None, max_length=100)
    fragmentation: Optional[str] = Field(default=None, max_length=100)
    pres_mode: Optional[str] = Field(default=None, max_length=100)
    preservation_quality: Optional[str] = Field(default=None, max_length=50)
    preservation_comments: Optional[str] = Field(default=None, sa_column=Column(Text))
    spatial_resolution: Optional[str] = Field(default=None, max_length=100)
    lagerstatten: Optional[str] = Field(default=None, max_length=100)
    orientation: Optional[str] = Field(default=None, max_length=100)
    abund_in_sediment: Optional[str] = Field(default=None, max_length=100)
    sorting: Optional[str] = Field(default=None, max_length=100)
    bioerosion: Optional[str] = Field(default=None, max_length=100)
    encrustation: Optional[str] = Field(default=None, max_length=100)
    abund_value: Optional[int] = Field(default=None)
    abund_unit: Optional[str] = Field(default=None, max_length=50)
    fossilsfrom1: Optional[str] = Field(default=None, max_length=10)
    size_classes: Optional[str] = Field(default=None, max_length=100)
    record_type: Optional[str] = Field(default=None, max_length=20)

    # PBDB comps block (collection body-part composition)
    articulated_parts: Optional[str] = Field(default=None, max_length=100)
    associated_parts: Optional[str] = Field(default=None, max_length=255)
    common_body_parts: Optional[str] = Field(default=None, max_length=255)
    rare_body_parts: Optional[str] = Field(default=None, max_length=255)
    feed_pred_traces: Optional[str] = Field(default=None, max_length=255)
    artifacts: Optional[str] = Field(default=None, max_length=255)
    component_comments: Optional[str] = Field(default=None, sa_column=Column(Text))

    # Ecology
    diet: Optional[str] = Field(default=None, max_length=100)
    environment: Optional[str] = Field(default=None, max_length=255)
    tectonic_setting: Optional[str] = Field(default=None, max_length=100)
    geology_comments: Optional[str] = Field(default=None, sa_column=Column(Text))
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

    # LLM enrichment (fossil_llm_enrich cron)
    llm_rock_type: Optional[str] = Field(default=None, max_length=64)
    llm_category: Optional[str] = Field(default=None, max_length=32)
    llm_subcategory: Optional[str] = Field(default=None, max_length=64)
    llm_preservation_quality: Optional[str] = Field(default=None, max_length=32)
    llm_completeness: Optional[str] = Field(default=None, max_length=32)
    llm_description: Optional[str] = Field(default=None, sa_column=Column(Text))
    llm_enriched: bool = Field(default=False, index=True)
