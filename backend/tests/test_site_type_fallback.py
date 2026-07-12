"""Tests for site type fallback when rock type is missing."""

from decimal import Decimal

from app.models.site_clean import SiteClean
from app.models.site_type import SiteType
from app.services.site_service.site_type_fallback import (
    effective_site_type,
    pick_site_type_for_period,
)
from app.services.site_service.summary import SiteRow, site_row_to_summary


def _site_type(
    *,
    type_id: int,
    period: str,
    rock_type: str,
    image_url: str | None = None,
) -> SiteType:
    return SiteType(
        id=type_id,
        period=period,
        rock_type=rock_type,
        main_image_url=image_url,
    )


def test_pick_site_type_for_period_is_deterministic_per_site_id():
    types_by_period = {
        "cretaceous": [
            _site_type(type_id=1, period="cretaceous", rock_type="sandstone", image_url="a.png"),
            _site_type(type_id=2, period="cretaceous", rock_type="limestone", image_url="b.png"),
        ],
    }

    first = pick_site_type_for_period(
        site_id=50001,
        period="cretaceous",
        types_by_period=types_by_period,
    )
    second = pick_site_type_for_period(
        site_id=50001,
        period="cretaceous",
        types_by_period=types_by_period,
    )

    assert first is not None
    assert first.id == second.id
    assert first.id in {1, 2}


def test_effective_site_type_uses_period_match_when_rock_type_missing():
    site = SiteClean(
        site_id=50001,
        min_age_ma=Decimal("72.00"),
        max_age_ma=Decimal("84.00"),
        rock_type=None,
        site_type_id=None,
    )
    row = SiteRow(site=site, site_type=None)
    types_by_period = {
        "cretaceous": [
            _site_type(
                type_id=10,
                period="cretaceous",
                rock_type="sandstone",
                image_url="https://example.com/cretaceous.png",
            ),
        ],
    }

    resolved = effective_site_type(site, None, types_by_period)

    assert resolved is not None
    assert resolved.period == "cretaceous"
    assert resolved.main_image_url.endswith("cretaceous.png")


def test_site_row_to_summary_applies_fallback_image():
    site = SiteClean(
        site_id=50001,
        min_age_ma=Decimal("72.00"),
        max_age_ma=Decimal("84.00"),
        rock_type=None,
        site_type_id=None,
    )
    row = SiteRow(site=site, site_type=None)
    types_by_period = {
        "cretaceous": [
            _site_type(
                type_id=10,
                period="cretaceous",
                rock_type="sandstone",
                image_url="https://example.com/cretaceous.png",
            ),
        ],
    }

    summary = site_row_to_summary(row, types_by_period=types_by_period)

    assert summary.site_type_id is None
    assert summary.site_type_period == "cretaceous"
    assert summary.site_type_rock_type == "sandstone"
    assert summary.main_image_url.endswith("cretaceous.png")
