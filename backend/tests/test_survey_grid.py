"""Tests for shared 200 m survey grid math."""

from __future__ import annotations

from app.services.site_common.survey_grid import (
    cell_indices,
    footprint_for_center,
    snap_to_cell_center,
    snap_wideness_m,
)


def test_snap_to_cell_center_is_stable() -> None:
    lat, lon = 50.8503, 4.3517
    c1 = snap_to_cell_center(lat, lon, cell_size_m=200.0)
    c2 = snap_to_cell_center(c1[0], c1[1], cell_size_m=200.0)
    assert abs(c1[0] - c2[0]) < 1e-9
    assert abs(c1[1] - c2[1]) < 1e-9
    ix1, iy1 = cell_indices(lat, lon, cell_size_m=200.0)
    ix2, iy2 = cell_indices(c1[0], c1[1], cell_size_m=200.0)
    assert (ix1, iy1) == (ix2, iy2)


def test_snap_wideness_to_cell_steps() -> None:
    assert snap_wideness_m(
        200, cell_size_m=200, min_wideness_m=200, max_wideness_m=2000
    ) == 200
    assert snap_wideness_m(
        350, cell_size_m=200, min_wideness_m=200, max_wideness_m=2000
    ) == 400
    assert snap_wideness_m(
        5000, cell_size_m=200, min_wideness_m=200, max_wideness_m=2000
    ) == 2000


def test_footprint_one_cell_and_even_bias() -> None:
    center = snap_to_cell_center(50.85, 4.35, cell_size_m=200.0)
    one = footprint_for_center(
        center[0], center[1], wideness_m=200.0, cell_size_m=200.0
    )
    assert one.n == 1
    assert abs(one.wideness_m - 200.0) < 1e-6
    assert one.west < one.east
    assert one.south < one.north

    two = footprint_for_center(
        center[0], center[1], wideness_m=400.0, cell_size_m=200.0
    )
    assert two.n == 2
    # Even N biases +E/+N → footprint larger than one cell on both axes.
    assert (two.east - two.west) > (one.east - one.west)
    assert (two.north - two.south) > (one.north - one.south)
