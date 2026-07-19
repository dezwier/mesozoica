"""Tests for site display labels used in notifications and push copy."""

from __future__ import annotations

from types import SimpleNamespace

from app.services.site_service.field_generate import FIELD_SITE_ID_START
from app.services.site_service.labels import site_display_title


def test_site_display_title_prefers_formation():
    site = SimpleNamespace(site_id=FIELD_SITE_ID_START + 7, formation="  Morrison  ")
    assert site_display_title(site) == "Morrison"


def test_site_display_title_uses_short_field_number():
    site = SimpleNamespace(site_id=FIELD_SITE_ID_START + 42, formation=None)
    assert site_display_title(site) == "#42"


def test_site_display_title_non_field_keeps_raw_id():
    site = SimpleNamespace(site_id=123, formation="")
    assert site_display_title(site) == "#123"


def test_site_display_title_none_is_empty():
    assert site_display_title(None) == ""
