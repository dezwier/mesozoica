"""Unit tests for dinosaur length/mass string parsing."""

from app.services.dinosaur_service.size_parse import (
    parse_length_m,
    parse_mass_kg,
    ranges_overlap,
)


def test_parse_length_single_meters():
    assert parse_length_m("12 m") == (12.0, 12.0)


def test_parse_length_range_with_tilde_and_en_dash():
    assert parse_length_m("~12 – 13 m") == (12.0, 13.0)


def test_parse_length_cm():
    assert parse_length_m("150 cm") == (1.5, 1.5)


def test_parse_length_range_hyphen():
    assert parse_length_m("5-10 m") == (5.0, 10.0)


def test_parse_length_rejects_mass_unit():
    assert parse_length_m("7 t") is None


def test_parse_mass_tonnes():
    assert parse_mass_kg("7 t") == (7000.0, 7000.0)
    assert parse_mass_kg("~6 – 9 tonnes") == (6000.0, 9000.0)


def test_parse_mass_kg():
    assert parse_mass_kg("700 kg") == (700.0, 700.0)


def test_parse_mass_range():
    assert parse_mass_kg("5-10 t") == (5000.0, 10000.0)


def test_parse_mass_rejects_length_unit():
    assert parse_mass_kg("12 m") is None


def test_parse_empty_and_null():
    assert parse_length_m(None) is None
    assert parse_length_m("") is None
    assert parse_mass_kg("   ") is None
    assert parse_mass_kg("unknown") is None


def test_ranges_overlap():
    assert ranges_overlap(5, 10, 8, 12) is True
    assert ranges_overlap(5, 10, 10, 15) is True
    assert ranges_overlap(5, 10, 11, 15) is False
    assert ranges_overlap(12, 12, 5, 20) is True
