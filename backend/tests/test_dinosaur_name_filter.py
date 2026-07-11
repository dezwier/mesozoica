"""Tests for dinosaur name filter helpers."""

from __future__ import annotations

from app.services.dinosaur_name_filter import parse_dino_names


def test_parse_dino_names_none():
    assert parse_dino_names(None) is None


def test_parse_dino_names_single():
    assert parse_dino_names(["Tyrannosaurus"]) == ["Tyrannosaurus"]


def test_parse_dino_names_multiple_and_comma_separated():
    assert parse_dino_names(["Tyrannosaurus", "Giganotosaurus, Parasaurolophus"]) == [
        "Tyrannosaurus",
        "Giganotosaurus",
        "Parasaurolophus",
    ]


def test_parse_dino_names_strips_whitespace():
    assert parse_dino_names([" Tyrannosaurus , Giganotosaurus "]) == [
        "Tyrannosaurus",
        "Giganotosaurus",
    ]
