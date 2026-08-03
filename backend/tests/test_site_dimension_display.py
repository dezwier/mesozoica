"""Tests for site odd_* display bands and exact-odds redaction."""

from __future__ import annotations

from app.services.site_service.dimension_display import (
    SiteDimensionKey,
    resolve_site_dimension_band,
)
from app.services.site_service.summary import SiteRow, site_row_to_summary
from app.models.site import Site


def test_resolve_site_dimension_band_precise_at_accuracy_1():
    band = resolve_site_dimension_band(
        dimension=SiteDimensionKey.DINO,
        true_value=0.42,
        accuracy=1.0,
        site_id=50001,
    )
    assert band.range_start == 0.42
    assert band.range_end == 0.42
    assert band.blur_sigma == 0.0
    assert band.effective_accuracy == 1.0


def test_depth_zero_is_always_precise():
    band = resolve_site_dimension_band(
        dimension=SiteDimensionKey.DEPTH,
        true_value=0.0,
        accuracy=0.0,
        site_id=7,
    )
    assert band.range_start == 0.0
    assert band.range_end == 0.0
    assert band.effective_accuracy == 1.0


def test_site_row_to_summary_redacts_exact_odds_by_default():
    site = Site(
        site_id=900001,
        odd_dino_count=0.42,
        odd_fossil_count=0.55,
        odd_completeness=0.61,
        odd_quality=0.33,
        odd_depth=0.78,
    )
    summary = site_row_to_summary(SiteRow(site=site, site_type=None))
    assert summary.odd_dino_count is None
    assert summary.odd_fossil_count is None
    assert summary.odd_completeness is None
    assert summary.odd_quality is None
    assert summary.odd_depth is None
    assert summary.odd_dino_band is not None
    assert summary.odd_depth_band is not None

    exact = site_row_to_summary(
        SiteRow(site=site, site_type=None),
        include_exact_odds=True,
    )
    assert exact.odd_dino_count == 0.42
    assert exact.odd_depth == 0.78
    assert exact.odd_dino_band is not None
