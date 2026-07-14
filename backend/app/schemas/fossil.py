"""Pydantic schemas for fossil API responses."""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict


class FossilSummary(BaseModel):
    """Card-facing fossil fields with joined dinosaur image data."""

    model_config = ConfigDict(from_attributes=True)

    id: int
    dinosaur_id: int
    identified_name: str | None = None
    identified_no: int | None = None
    identified_rank: str | None = None
    taxon_difference: str | None = None
    accepted_name: str | None = None
    accepted_no: int | None = None
    accepted_rank: str | None = None
    accepted_attr: str | None = None
    genus: str | None = None
    family: str | None = None
    taxon_order: str | None = None
    taxon_class: str | None = None
    phylum: str | None = None
    latitude: float | None = None
    longitude: float | None = None
    country_code: str | None = None
    state: str | None = None
    county: str | None = None
    altitude_value: float | None = None
    altitude_unit: str | None = None
    protected: str | None = None
    geogcomments: str | None = None
    geogscale: str | None = None
    geoplate: int | None = None
    latlng_basis: str | None = None
    latlng_precision: int | None = None
    paleolat: float | None = None
    paleolng: float | None = None
    paleomodel: str | None = None
    paleoage: str | None = None
    geological_formation: str | None = None
    geological_group: str | None = None
    geological_member: str | None = None
    strat_zone: str | None = None
    localsection: str | None = None
    localbed: str | None = None
    localbedunit: str | None = None
    localorder: str | None = None
    regionalsection: str | None = None
    regionalbed: str | None = None
    regionalbedunit: str | None = None
    regionalorder: str | None = None
    min_age_ma: float | None = None
    max_age_ma: float | None = None
    early_interval: str | None = None
    late_interval: str | None = None
    stratcomments: str | None = None
    stratscale: str | None = None
    lithdescript: str | None = None
    lithology1: str | None = None
    lithadj1: str | None = None
    lithification1: str | None = None
    minor_lithology1: str | None = None
    lithology2: str | None = None
    lithadj2: str | None = None
    lithification2: str | None = None
    minor_lithology2: str | None = None
    fossilsfrom2: str | None = None
    concentration: str | None = None
    temporal_resolution: str | None = None
    collection_name: str | None = None
    collection_aka: str | None = None
    collection_no: int | None = None
    collection_dates: str | None = None
    collection_type: str | None = None
    collection_methods: str | None = None
    collectors: str | None = None
    museum: str | None = None
    research_group: str | None = None
    collection_coverage: str | None = None
    collection_size: str | None = None
    rock_censused: str | None = None
    collection_comments: str | None = None
    taxonomy_comments: str | None = None
    occurrence_comments: str | None = None
    composition: str | None = None
    architecture: str | None = None
    thickness: str | None = None
    reinforcement: str | None = None
    plant_organ: str | None = None
    fragmentation: str | None = None
    pres_mode: str | None = None
    preservation_quality: str | None = None
    preservation_comments: str | None = None
    spatial_resolution: str | None = None
    lagerstatten: str | None = None
    orientation: str | None = None
    abund_in_sediment: str | None = None
    sorting: str | None = None
    bioerosion: str | None = None
    encrustation: str | None = None
    abund_value: int | None = None
    abund_unit: str | None = None
    fossilsfrom1: str | None = None
    size_classes: str | None = None
    record_type: str | None = None
    articulated_parts: str | None = None
    associated_parts: str | None = None
    common_body_parts: str | None = None
    rare_body_parts: str | None = None
    feed_pred_traces: str | None = None
    artifacts: str | None = None
    component_comments: str | None = None
    diet: str | None = None
    environment: str | None = None
    tectonic_setting: str | None = None
    geology_comments: str | None = None
    taxon_environment: str | None = None
    life_habit: str | None = None
    motility: str | None = None
    reproduction: str | None = None
    ontogeny: str | None = None
    reference_no: int | None = None
    ref_author: str | None = None
    ref_pubyr: int | None = None
    reid_no: int | None = None
    description: str | None = None
    main_image_url: str | None = None
    llm_rock_type: str | None = None
    llm_category: str | None = None
    llm_subcategory: str | None = None
    llm_preservation_quality: str | None = None
    llm_completeness: str | None = None
    dinosaur_name: str
    dinosaur_main_image_url: str | None = None
    site_id: int | None = None
    site_main_image_url: str | None = None


class FossilListResponse(BaseModel):
    items: list[FossilSummary]
    total: int
    limit: int
    offset: int
    has_next: bool
