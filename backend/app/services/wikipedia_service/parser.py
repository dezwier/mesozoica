"""Parse Wikipedia Parsoid HTML into dinosaur fields."""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any
from urllib.parse import unquote

from bs4 import BeautifulSoup

_WIKI_BASE = "https://en.wikipedia.org/wiki/"
_MA_RANGE_RE = re.compile(
    r"(\d+(?:\.\d+)?)\s*[–\-—]\s*(\d+(?:\.\d+)?)\s*(?:<[^>]+>)*\s*Ma",
    re.IGNORECASE,
)
_PERIOD_RE = re.compile(
    r"Temporal range:\s*(?:<[^>]+>|\s)*([^,<(]+)",
    re.IGNORECASE,
)
_TAXON_RANKS = (
    "kingdom",
    "phylum",
    "division",
    "class",
    "order",
    "family",
    "subfamily",
    "tribe",
    "genus",
    "species",
)
_DIET_KEYWORDS = (
    ("herbivore", "herbivore"),
    ("herbivorous", "herbivore"),
    ("carnivore", "carnivore"),
    ("carnivorous", "carnivore"),
    ("omnivore", "omnivore"),
    ("omnivorous", "omnivore"),
    ("insectivore", "insectivore"),
    ("piscivore", "piscivore"),
    ("filter feeder", "filter feeder"),
    ("filter-feeder", "filter feeder"),
)


@dataclass(frozen=True)
class ParsedArticle:
    birth: float | None
    death: float | None
    period: str | None
    cladogram: dict[str, Any]
    diet_type: str | None
    long_description: str | None
    article_html: str


def _normalize_rank(label: str) -> str | None:
    cleaned = label.strip().lower().rstrip(":")
    if cleaned.startswith("clade"):
        return "clade"
    for rank in _TAXON_RANKS:
        if cleaned == rank or cleaned.startswith(rank):
            return rank
    return None


def _clean_taxon_value(text: str) -> str:
    text = re.sub(r"[†‡]", "", text)
    text = re.sub(r"\s+", " ", text).strip()
    text = re.sub(r"\s+[A-Z][A-Za-z.-]+(?:\s+(?:et al\.|& al\.))?,?\s+\d{4}$", "", text)
    return text.strip()


def _extract_infobox_text(html: str) -> str:
    soup = BeautifulSoup(html, "html.parser")
    box = soup.select_one("table.infobox.biota")
    return str(box) if box else ""


def _parse_ma_range(infobox_html: str) -> tuple[float | None, float | None]:
    match = _MA_RANGE_RE.search(infobox_html)
    if not match:
        return None, None
    earliest = float(match.group(1))
    latest = float(match.group(2))
    return max(earliest, latest), min(earliest, latest)


def _parse_period(infobox_html: str) -> str | None:
    match = _PERIOD_RE.search(infobox_html)
    if not match:
        return None
    period = match.group(1).strip()
    period = re.sub(r"\s+", " ", period)
    return period or None


def _parse_cladogram(soup: BeautifulSoup) -> dict[str, Any]:
    cladogram: dict[str, Any] = {}
    box = soup.select_one("table.infobox.biota")
    if not box:
        return {"kingdom": "Animalia"}

    clade_index = 0
    for row in box.find_all("tr"):
        cells = row.find_all(["th", "td"])
        if len(cells) < 2:
            continue
        label = cells[0].get_text(" ", strip=True)
        value = _clean_taxon_value(cells[1].get_text(" ", strip=True))
        if not value:
            continue

        rank = _normalize_rank(label)
        if rank is None:
            continue

        if rank == "clade":
            clade_index += 1
            key = f"clade_{clade_index}" if clade_index > 1 or "clade" in cladogram else "clade"
            cladogram[key] = value
        else:
            cladogram[rank] = value

    if "kingdom" not in cladogram:
        cladogram = {"kingdom": "Animalia", **cladogram}
    return cladogram


def _parse_diet_from_infobox(soup: BeautifulSoup) -> str | None:
    box = soup.select_one("table.infobox.biota")
    if not box:
        return None
    for row in box.find_all("tr"):
        cells = row.find_all(["th", "td"])
        if len(cells) < 2:
            continue
        label = cells[0].get_text(" ", strip=True).lower()
        if label.startswith("diet"):
            return _clean_taxon_value(cells[1].get_text(" ", strip=True)) or None
    return None


def _parse_diet_from_lead(soup: BeautifulSoup) -> str | None:
    for paragraph in soup.find_all("p"):
        text = paragraph.get_text(" ", strip=True).lower()
        if len(text) < 40:
            continue
        for keyword, diet in _DIET_KEYWORDS:
            if keyword in text:
                return diet
        break
    return None


def _first_lead_paragraph(soup: BeautifulSoup) -> str | None:
    infobox = soup.select_one("table.infobox.biota")
    if infobox is not None:
        for paragraph in infobox.find_all_next("p"):
            text = paragraph.get_text(" ", strip=True)
            if len(text) >= 40:
                return text
        return None

    for paragraph in soup.find_all("p"):
        text = paragraph.get_text(" ", strip=True)
        if len(text) >= 40:
            return text
    return None


def _rewrite_links(soup: BeautifulSoup, base_url: str) -> None:
    wiki_root = base_url.rstrip("/")
    for anchor in soup.find_all("a", href=True):
        href = str(anchor["href"])
        if href.startswith("./"):
            path = unquote(href[2:]).replace(" ", "_")
            anchor["href"] = f"{wiki_root}/{path}"
        elif href.startswith("/wiki/"):
            anchor["href"] = f"{wiki_root}/{unquote(href[len('/wiki/'):]).replace(' ', '_')}"


def rewrite_article_links(html: str, base_url: str = "https://en.wikipedia.org/wiki/") -> str:
    """Rewrite relative Wikipedia links to absolute URLs."""
    soup = BeautifulSoup(html, "html.parser")
    _rewrite_links(soup, base_url)
    return str(soup)


def parse_article_html(html: str) -> ParsedArticle:
    """Extract dinosaur fields from full Parsoid HTML."""
    soup = BeautifulSoup(html, "html.parser")
    infobox_html = _extract_infobox_text(html)
    birth, death = _parse_ma_range(infobox_html)
    period = _parse_period(infobox_html)
    cladogram = _parse_cladogram(soup)
    diet = _parse_diet_from_infobox(soup) or _parse_diet_from_lead(soup)
    long_description = _first_lead_paragraph(soup)
    article_html = rewrite_article_links(html)
    return ParsedArticle(
        birth=birth,
        death=death,
        period=period,
        cladogram=cladogram,
        diet_type=diet,
        long_description=long_description,
        article_html=article_html,
    )
