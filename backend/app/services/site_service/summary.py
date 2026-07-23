"""Map joined site rows to API schemas."""

from __future__ import annotations

from dataclasses import dataclass
from decimal import Decimal

from app.models.site import Site
from app.models.site_type import SiteType
from app.schemas.site import SiteSummary
from app.services.site_service.site_type_fallback import effective_site_type


@dataclass(frozen=True)
class SiteRow:
    site: Site
    site_type: SiteType | None
    status: str | None = None
    viewer_has_surveyed: bool | None = None


def site_row_to_summary(
    row: SiteRow,
    *,
    types_by_period: dict[str, list[SiteType]] | None = None,
) -> SiteSummary:
    site = row.site
    site_type = (
        effective_site_type(site, row.site_type, types_by_period)
        if types_by_period is not None
        else row.site_type
    )
    return SiteSummary(
        site_id=site.site_id,
        latitude=_decimal_to_float(site.latitude),
        longitude=_decimal_to_float(site.longitude),
        country_code=site.country_code,
        state=site.state,
        rock_type=site.rock_type,
        formation=site.formation,
        min_age_ma=_decimal_to_float(site.min_age_ma),
        max_age_ma=_decimal_to_float(site.max_age_ma),
        site_type_id=site.site_type_id,
        site_type_period=site_type.period if site_type else None,
        site_type_rock_type=site_type.rock_type if site_type else None,
        main_image_url=site_type.main_image_url if site_type else None,
        data_source=site.data_source,
        how_discovered=site.how_discovered,
        status=row.status,
        viewer_has_surveyed=row.viewer_has_surveyed,
        odd_dino_count=site.odd_dino_count,
        odd_fossil_count=site.odd_fossil_count,
        odd_completeness=site.odd_completeness,
        odd_quality=site.odd_quality,
        odd_depth=site.odd_depth,
    )


def _decimal_to_float(value: Decimal | float | int | None) -> float | None:
    if value is None:
        return None
    return float(value)
