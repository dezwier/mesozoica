"""Tests for Wikipedia category listing helpers."""

from __future__ import annotations

from unittest.mock import MagicMock

import pytest

from app.services.wikipedia_service.category import (
    CategoryMember,
    is_wikipedia_list_title,
    list_category_articles,
    list_dinosaur_sync_batches,
    list_dinosaur_sync_candidates,
    merge_category_members,
)


def test_is_wikipedia_list_title():
    assert is_wikipedia_list_title(
        "List of non-avian dinosaur species preserved with evidence of feathers"
    )
    assert is_wikipedia_list_title("lists of dinosaurs")
    assert not is_wikipedia_list_title("Tyrannosaurus")
    assert not is_wikipedia_list_title("Liston")


def test_list_category_articles_skips_list_pages():
    client = MagicMock()
    client.action_api.return_value = {
        "query": {
            "categorymembers": [
                {"pageid": 1, "title": "Archaeopteryx"},
                {
                    "pageid": 2,
                    "title": (
                        "List of non-avian dinosaur species preserved "
                        "with evidence of feathers"
                    ),
                },
                {"pageid": 3, "title": "Velociraptor"},
            ]
        }
    }

    members = list_category_articles(client, "Category:Feathered dinosaurs")

    assert [member.title for member in members] == [
        "Archaeopteryx",
        "Velociraptor",
    ]


def test_merge_category_members_deduplicates_by_page_id():
    primary = [
        CategoryMember(page_id=1, title="Tyrannosaurus"),
        CategoryMember(page_id=2, title="Velociraptor"),
    ]
    feathered = [
        CategoryMember(page_id=1, title="Tyrannosaurus"),
        CategoryMember(page_id=3, title="Archaeopteryx"),
    ]

    merged = merge_category_members(primary, feathered)

    assert [member.title for member in merged] == [
        "Tyrannosaurus",
        "Velociraptor",
        "Archaeopteryx",
    ]


def test_merge_category_members_deduplicates_by_title_when_page_id_missing():
    primary = [CategoryMember(page_id=0, title="Archaeopteryx")]
    feathered = [CategoryMember(page_id=0, title="archaeopteryx")]

    merged = merge_category_members(primary, feathered)

    assert len(merged) == 1
    assert merged[0].title == "Archaeopteryx"


def test_list_dinosaur_sync_batches_returns_separate_categories(monkeypatch):
    client = MagicMock()
    calls: list[str | None] = []

    def fake_list_category(_client, category, *, max_pages=None):
        calls.append(category)
        if category == "Category:Dinosaur_genera":
            return [CategoryMember(page_id=1, title="Tyrannosaurus")]
        if category == "Category:Feathered dinosaurs":
            return [
                CategoryMember(page_id=1, title="Tyrannosaurus"),
                CategoryMember(page_id=2, title="Archaeopteryx"),
            ]
        raise AssertionError(f"unexpected category: {category}")

    monkeypatch.setattr(
        "app.services.wikipedia_service.category.list_category_articles",
        fake_list_category,
    )

    batches = list_dinosaur_sync_batches(client)

    assert calls == ["Category:Dinosaur_genera", "Category:Feathered dinosaurs"]
    assert [name for name, _ in batches] == [
        "Category:Dinosaur_genera",
        "Category:Feathered dinosaurs",
    ]
    assert [member.title for _, members in batches for member in members] == [
        "Tyrannosaurus",
        "Archaeopteryx",
    ]


def test_list_dinosaur_sync_candidates_merges_default_categories(monkeypatch):
    client = MagicMock()
    calls: list[str | None] = []

    def fake_list_category(_client, category, *, max_pages=None):
        calls.append(category)
        if category == "Category:Dinosaur_genera":
            return [CategoryMember(page_id=1, title="Tyrannosaurus")]
        if category == "Category:Feathered dinosaurs":
            return [
                CategoryMember(page_id=1, title="Tyrannosaurus"),
                CategoryMember(page_id=2, title="Archaeopteryx"),
            ]
        raise AssertionError(f"unexpected category: {category}")

    monkeypatch.setattr(
        "app.services.wikipedia_service.category.list_category_articles",
        fake_list_category,
    )

    members = list_dinosaur_sync_candidates(client)

    assert calls == ["Category:Dinosaur_genera", "Category:Feathered dinosaurs"]
    assert [member.title for member in members] == ["Tyrannosaurus", "Archaeopteryx"]


def test_list_dinosaur_sync_batches_honors_explicit_category(monkeypatch):
    client = MagicMock()

    monkeypatch.setattr(
        "app.services.wikipedia_service.category.list_category_articles",
        lambda *_args, **_kwargs: [CategoryMember(page_id=9, title="OnlyOne")],
    )

    batches = list_dinosaur_sync_batches(
        client,
        category="Category:Custom",
        max_pages=5,
    )

    assert batches == [("Category:Custom", [CategoryMember(page_id=9, title="OnlyOne")])]


def test_list_dinosaur_sync_candidates_honors_explicit_category(monkeypatch):
    client = MagicMock()

    monkeypatch.setattr(
        "app.services.wikipedia_service.category.list_category_articles",
        lambda *_args, **_kwargs: [CategoryMember(page_id=9, title="OnlyOne")],
    )

    members = list_dinosaur_sync_candidates(
        client,
        category="Category:Custom",
        max_pages=5,
    )

    assert [member.title for member in members] == ["OnlyOne"]


def test_list_dinosaur_sync_batches_applies_global_max_pages(monkeypatch):
    client = MagicMock()

    def fake_list_category(_client, category, *, max_pages=None):
        if category == "Category:Dinosaur_genera":
            return [
                CategoryMember(page_id=1, title="A"),
                CategoryMember(page_id=2, title="B"),
            ]
        return [CategoryMember(page_id=3, title="C")]

    monkeypatch.setattr(
        "app.services.wikipedia_service.category.list_category_articles",
        fake_list_category,
    )

    batches = list_dinosaur_sync_batches(client, max_pages=2)

    assert [member.title for _, members in batches for member in members] == ["A", "B"]


def test_list_dinosaur_sync_candidates_applies_global_max_pages(monkeypatch):
    client = MagicMock()

    def fake_list_category(_client, category, *, max_pages=None):
        if category == "Category:Dinosaur_genera":
            return [
                CategoryMember(page_id=1, title="A"),
                CategoryMember(page_id=2, title="B"),
            ]
        return [CategoryMember(page_id=3, title="C")]

    monkeypatch.setattr(
        "app.services.wikipedia_service.category.list_category_articles",
        fake_list_category,
    )

    members = list_dinosaur_sync_candidates(client, max_pages=2)

    assert [member.title for member in members] == ["A", "B"]
