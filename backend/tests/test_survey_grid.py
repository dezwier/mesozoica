"""Tests for shared 200 m survey grid math."""

from __future__ import annotations

from app.services.site_common.survey_grid import (
    cell_indices,
    cell_latlon_bbox,
    cell_meter_bounds,
    footprint_for_center,
    meters_to_latlon,
    point_in_cell,
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


def test_cell_meter_bounds_and_point_in_cell() -> None:
    cell = 500.0
    ix, iy = 10, 20
    x0, x1, y0, y1 = cell_meter_bounds(ix, iy, cell_size_m=cell)
    assert (x1 - x0, y1 - y0) == (cell, cell)
    inside = meters_to_latlon((x0 + x1) / 2, (y0 + y1) / 2)
    assert point_in_cell(inside[0], inside[1], ix=ix, iy=iy, cell_size_m=cell)
    outside = meters_to_latlon(x1 + 1.0, (y0 + y1) / 2)
    assert not point_in_cell(outside[0], outside[1], ix=ix, iy=iy, cell_size_m=cell)
    south, north, west, east = cell_latlon_bbox(ix, iy, cell_size_m=cell)
    assert south < north and west < east


def test_footprint_one_cell_and_even_bias() -> None:
    center = snap_to_cell_center(50.85, 4.35, cell_size_m=500.0)
    one = footprint_for_center(
        center[0], center[1], wideness_m=500.0, cell_size_m=500.0
    )
    assert one.n == 1
    assert abs(one.wideness_m - 500.0) < 1e-6
    assert one.west < one.east
    assert one.south < one.north
    assert len(one.cell_centers()) == 1

    two = footprint_for_center(
        center[0], center[1], wideness_m=1000.0, cell_size_m=500.0
    )
    assert two.n == 2
    assert len(two.cell_centers()) == 4
    # Even N biases +E/+N → footprint larger than one cell on both axes.
    assert (two.east - two.west) > (one.east - one.west)
    assert (two.north - two.south) > (one.north - one.south)
