"""Tests for fossil clean normalization rules."""

from __future__ import annotations

from decimal import Decimal

from app.models.fossil import Fossil
from app.services.fossil_clean_service.rules import (
    ages_for_site,
    clean_preservation_quality,
    formation_for_fossil,
    formation_from_text,
    fossil_comment,
    fossil_name,
    fossil_type,
    infer_preservation_quality,
    parse_collection_years,
    period_for_ages,
    rock_type_for_site,
    rock_type_from_fossil,
    rock_type_from_lithology,
    sub_category,
)


def test_fossil_type_defaults_to_body():
    assert fossil_type(None) == "body"
    assert fossil_type("body") == "body"
    assert fossil_type("body,trace") == "body"
    assert fossil_type("body,mold/impression") == "body"


def test_fossil_type_trace_only():
    assert fossil_type("trace") == "trace"
    assert fossil_type("cast,trace") == "trace"
    assert fossil_type("mold/impression,trace") == "trace"


def test_sub_category_normalizes_multi_value_parts():
    result = sub_category(
        fossil_kind="body",
        common_body_parts="partial skeletons,vertebrae,limb elements",
        rare_body_parts="teeth",
        associated_parts=None,
        feed_pred_traces=None,
        occurrence_comments=None,
        component_comments=None,
    )
    assert result == "limb,skeleton,tooth,vertebra"


def test_sub_category_extracts_bones_from_comments():
    result = sub_category(
        fossil_kind="body",
        common_body_parts=None,
        rare_body_parts=None,
        associated_parts=None,
        feed_pred_traces=None,
        occurrence_comments="MPCA-Pv 27177, L femur and vertebrae",
        component_comments=None,
    )
    assert result == "femur,vertebra"


def test_sub_category_body_includes_trace_only_from_feed_pred_traces():
    result = sub_category(
        fossil_kind="body",
        common_body_parts=None,
        rare_body_parts=None,
        associated_parts=None,
        feed_pred_traces="tooth marks",
        occurrence_comments="tooth marks on bone",
        component_comments=None,
    )
    assert result == "tooth,tooth_mark"


def test_sub_category_trace_includes_footprints():
    result = sub_category(
        fossil_kind="trace",
        common_body_parts="footprints",
        rare_body_parts=None,
        associated_parts=None,
        feed_pred_traces=None,
        occurrence_comments=None,
        component_comments=None,
    )
    assert result == "footprint"


def test_parse_collection_years_single_and_ranges():
    assert parse_collection_years("1946, 1962") == (1946, 1962)
    assert parse_collection_years("1879-1887") == (1879, 1887)
    assert parse_collection_years("2009–") == (2009, 2009)
    assert parse_collection_years(None) == (None, None)


def test_rock_type_from_lithology_prefers_lithology1():
    assert rock_type_from_lithology("sandstone", "channel fill") == "sandstone"
    assert rock_type_from_lithology("not reported", "concretionary mudstone") == "mudstone"
    assert rock_type_from_lithology(None, None) is None


def test_rock_type_for_site_picks_most_common():
    fossils = [
        Fossil(
            id=1,
            dinosaur_id=1,
            collection_no=100,
            lithology1="sandstone",
        ),
        Fossil(
            id=2,
            dinosaur_id=1,
            collection_no=100,
            lithology1="sandstone",
        ),
        Fossil(
            id=3,
            dinosaur_id=1,
            collection_no=100,
            lithology1="mudstone",
        ),
    ]
    assert rock_type_for_site(fossils) == "sandstone"


def test_ages_for_site_spans_member_fossils():
    fossils = [
        Fossil(id=1, dinosaur_id=1, collection_no=100, min_age_ma=Decimal("66.00"), max_age_ma=Decimal("72.00")),
        Fossil(id=2, dinosaur_id=1, collection_no=100, min_age_ma=Decimal("70.00"), max_age_ma=Decimal("80.00")),
    ]
    assert ages_for_site(fossils) == (Decimal("66.00"), Decimal("80.00"))


def test_period_for_ages_maps_mesozoic_periods():
    assert period_for_ages(Decimal("210.00"), Decimal("220.00")) == "triassic"
    assert period_for_ages(Decimal("150.00"), Decimal("160.00")) == "jurassic"
    assert period_for_ages(Decimal("66.00"), Decimal("72.20")) == "cretaceous"
    assert period_for_ages(None, None) is None


def test_clean_preservation_quality_lowercases():
    assert clean_preservation_quality("Good") == "good"
    assert clean_preservation_quality(None) is None


def test_parse_collection_years_complex_list():
    years = parse_collection_years("1927, 1929–1931, 1939–1941, 1960–1967, 1975-1990, 2001–2002, 2012")
    assert years == (1927, 2012)


def test_fossil_name_prefers_identified_name():
    assert fossil_name(identified_name="Tyrannosaurus rex", accepted_name="T. rex", genus="Tyrannosaurus") == (
        "Tyrannosaurus rex"
    )


def test_formation_from_text_extracts_from_stratcomments():
    text = "near base of Mesaverde Group, 100 ft. above Sego Mbr. of Price River Fm."
    assert formation_from_text(text) == "Price River"


def test_formation_for_fossil_falls_back_to_stratcomments():
    fossil = Fossil(
        id=1,
        dinosaur_id=1,
        collection_no=10,
        stratcomments="Customarily referred to the Sînpetru Formation",
    )
    assert formation_for_fossil(fossil) == "Sînpetru"


def test_rock_type_from_fossil_uses_stratcomments():
    fossil = Fossil(
        id=1,
        dinosaur_id=1,
        collection_no=10,
        lithology1="not reported",
        stratcomments="red-coloured silty sandstone with mudstone lenses",
    )
    assert rock_type_from_fossil(fossil) == "sandstone"


def test_infer_preservation_quality_from_fragmentation():
    assert infer_preservation_quality(
        preservation_quality=None,
        fragmentation="frequent",
        architecture=None,
    ) == "poor"


def test_infer_preservation_quality_from_architecture():
    assert infer_preservation_quality(
        preservation_quality=None,
        fragmentation=None,
        architecture="compact or dense",
    ) == "good"


def test_sub_category_uses_articulated_parts_and_comments():
    result = sub_category(
        fossil_kind="body",
        common_body_parts=None,
        rare_body_parts=None,
        associated_parts=None,
        feed_pred_traces=None,
        occurrence_comments="FC-DPV 443, anterior caudal vertebra",
        component_comments=None,
        pres_mode=None,
        articulated_parts="some",
    )
    assert result == "partial_skeleton,vertebra"


def test_fossil_comment_concatenates_freetext_fields():
    fossil = Fossil(
        id=1,
        dinosaur_id=1,
        collection_no=10,
        occurrence_comments="partial skull and vertebrae",
        stratcomments="52 m above base (Kneehills Tuff)",
        collectors="C. M. Sternberg",
        common_body_parts="skull, vertebrae",
        pres_mode="body",
    )
    result = fossil_comment(fossil)
    assert result is not None
    assert "Occurrence: partial skull and vertebrae" in result
    assert "Stratigraphy: 52 m above base (Kneehills Tuff)" in result
    assert "Collectors: C. M. Sternberg" in result
    assert "Body parts: skull, vertebrae" in result
    assert "Preservation mode: body" in result
    assert " | " in result


def test_fossil_comment_deduplicates_repeated_text():
    fossil = Fossil(
        id=1,
        dinosaur_id=1,
        collection_no=10,
        occurrence_comments="partial skull",
        component_comments="partial skull",
    )
    result = fossil_comment(fossil)
    assert result == "Occurrence: partial skull"
