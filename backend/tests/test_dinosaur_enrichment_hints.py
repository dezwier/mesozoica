"""Tests for size hint extraction."""

from app.services.dinosaur_enrichment_service.infobox_hints import extract_size_from_text, extract_size_hints


def test_extract_size_from_text_combined_phrase():
    text = (
        "It is estimated to have reached a length of 17.5 metres (57 ft) "
        "and mass of 14 tonnes (15 short tons)."
    )
    hints = extract_size_from_text(text)
    assert hints["length_hint"] == "17.5 m"
    assert hints["mass_hint"] == "14 t"


def test_extract_size_from_text_measuring_no_more_than():
    text = "It was rather small, measuring no more than 9.1 metres (30 ft) long."
    hints = extract_size_from_text(text)
    assert hints["length_hint"] == "9.1 m"


def test_extract_size_from_text_holtz_length():
    text = "In 2012 Thomas Holtz gave a length of 18.3 metres (60 ft)."
    hints = extract_size_from_text(text)
    assert hints["length_hint"] == "18.3 m"


def test_extract_size_from_text_length_and_mass_pair():
    text = "Others gave a similar size at 7.2 metres (23.6 feet) and 1.65 tonnes (1.82 short tons)."
    hints = extract_size_from_text(text)
    assert hints["length_hint"] == "7.2 m"
    assert hints["mass_hint"] == "1.65 t"


def test_extract_size_from_text_kg_or_less():
    text = "Most dinosaurs in their time period weighed 40 kg or less."
    hints = extract_size_from_text(text)
    assert hints["mass_hint"] == "40 kg"


def test_extract_size_hints_from_article_html():
    html = "<html><body><p>It is estimated to have reached a length of 12 meters and mass of 7 tonnes.</p></body></html>"
    hints = extract_size_hints(html)
    assert hints["length_hint"] == "12 m"
    assert hints["mass_hint"] == "7 t"
