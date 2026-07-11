"""Parse Wikipedia Parsoid HTML into dinosaur fields."""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any
from urllib.parse import quote, unquote

from bs4 import BeautifulSoup

_WIKI_BASE = "https://en.wikipedia.org/wiki/"
_MA_RANGE_RE = re.compile(
    r"(\d+(?:\.\d+)?)\s*[–\-—]\s*(\d+(?:\.\d+)?)\s*Ma\b",
    re.IGNORECASE,
)
_MA_RANGE_HTML_RE = re.compile(
    r"(\d+(?:\.\d+)?)\s*[–\-—]\s*(\d+(?:\.\d+)?)\s*(?:<[^>]+>)*\s*Ma",
    re.IGNORECASE,
)
_MA_SINGLE_RE = re.compile(
    r"(\d+(?:\.\d+)?)\s*Ma\b",
    re.IGNORECASE,
)
_MA_SINGLE_HTML_RE = re.compile(
    r"(\d+(?:\.\d+)?)\s*(?:<[^>]+>)*\s*Ma",
    re.IGNORECASE,
)
_PERIOD_RE = re.compile(
    r"Temporal range:\s*(?:<[^>]+>|\s)*([^,<(]+)",
    re.IGNORECASE,
)
_PERIOD_TEXT_RE = re.compile(
    r"Temporal range:\s*([^,]+?)(?:\s*,|\s+\d|\s*$)",
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
    return _strip_taxonomic_authority(text)


def _strip_taxonomic_authority(text: str) -> str:
    """Remove author/year suffixes from plain-text taxon values."""
    text = text.strip()
    if not text:
        return text

    # Parenthetical authority, e.g. "Name (Osborn, 1905)".
    text = re.sub(r"\s*\([^)]*\b\d{3,4}\b[^)]*\)\s*$", "", text).strip()

    # Repeatedly strip trailing authority fragments (with or without year).
    # Case-sensitive: lowercase species epithets like "rex" must not match.
    trailing_authority = re.compile(
        r"\s+(?:"
        r"(?:[A-Z][A-Za-z.-]*(?:\s+[A-Z]\.?)*(?:\s+(?:&|and)\s+[A-Z][A-Za-z.-]*)*\s+)?"
        r"(?i:(?:et\s+al\.?|et\s+all\.?))"
        r"(?:,\s*)?"
        r"(?:\d{3,4})?"
        r"|"
        r"(?:[A-Z][A-Za-z.-]*(?:\s+[A-Z]\.?)*(?:\s+(?:&|and)\s+[A-Z][A-Za-z.-]*)*)"
        r"(?:,\s*|\s+)\d{3,4}"
        r")\s*$",
    )
    while True:
        stripped = trailing_authority.sub("", text).strip()
        if stripped == text:
            break
        text = stripped

    return text


_AUTHORITY_ITALIC_FRAGMENT = re.compile(
    r"^(?:et\s+al\.?|et\s+all\.?|\d{3,4})$",
    re.IGNORECASE,
)


def _finalize_taxon_name(text: str) -> str:
    return _strip_taxonomic_authority(text)


def _extract_infobox_taxon_value(cell) -> str:
    """Extract taxon name from an infobox cell, omitting finder/author citations."""
    fragment = BeautifulSoup(str(cell), "html.parser")
    for tag in fragment.select(".authority, .taxon-auth"):
        tag.decompose()

    italic_parts = [
        re.sub(r"[†‡]", "", tag.get_text(" ", strip=True))
        for tag in fragment.find_all("i")
    ]
    italic_parts = [
        part
        for part in italic_parts
        if part and not _AUTHORITY_ITALIC_FRAGMENT.match(part.strip())
    ]
    if italic_parts:
        return _finalize_taxon_name(" ".join(italic_parts))

    return _finalize_taxon_name(fragment.get_text(" ", strip=True))


def _extract_infobox_text(html: str) -> str:
    soup = BeautifulSoup(html, "html.parser")
    box = soup.select_one("table.infobox.biota")
    return str(box) if box else ""


def _infobox_plain_text(soup: BeautifulSoup) -> str:
    box = soup.select_one("table.infobox.biota")
    if not box:
        return ""
    return box.get_text(" ", strip=True)


def _temporal_search_window(source: str, *, max_len: int = 500) -> str:
    idx = source.lower().find("temporal range")
    if idx >= 0:
        return source[idx : idx + max_len]
    return source[:max_len]


def _parse_ma_range(infobox_html: str, infobox_text: str = "") -> tuple[float | None, float | None]:
    for source in (infobox_text, infobox_html):
        if not source:
            continue
        pattern = _MA_RANGE_RE if source == infobox_text else _MA_RANGE_HTML_RE
        match = pattern.search(_temporal_search_window(source))
        if match:
            earliest = float(match.group(1))
            latest = float(match.group(2))
            return max(earliest, latest), min(earliest, latest)

    for source in (infobox_text, infobox_html):
        if not source:
            continue
        pattern = _MA_SINGLE_RE if source == infobox_text else _MA_SINGLE_HTML_RE
        match = pattern.search(_temporal_search_window(source))
        if match:
            value = float(match.group(1))
            return value, value

    return None, None


def _parse_period(infobox_html: str, infobox_text: str = "") -> str | None:
    match = _PERIOD_RE.search(infobox_html)
    if match:
        period = match.group(1).strip()
        period = re.sub(r"\s+", " ", period)
        if period:
            return period

    if infobox_text:
        text_match = _PERIOD_TEXT_RE.search(infobox_text)
        if text_match:
            period = re.sub(r"\s+", " ", text_match.group(1).strip())
            if period:
                return period
    return None


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
        value = _extract_infobox_taxon_value(cells[1])
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
            return _extract_infobox_taxon_value(cells[1]) or None
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


_WIKI_SITE = "https://en.wikipedia.org"
_COMMONS_FILE_PATH = "https://commons.wikimedia.org/wiki/Special:FilePath/"

_READER_MODE_SELECTORS = (
    ".navbox",
    ".vertical-navbox",
    ".sisterproject",
    ".metadata",
    ".ambox",
    ".references",
    ".mw-references-wrap",
    ".mw-editsection",
    ".noprint",
    '[role="navigation"]',
)

_SECTION_HEADING_IDS = frozenset(
    {
        "references",
        "notes",
        "bibliography",
        "external_links",
        "see_also",
        "further_reading",
    }
)


def _rewrite_media_urls(soup: BeautifulSoup) -> None:
    """Make image and asset URLs absolute so they load outside Wikipedia."""
    for img in soup.find_all("img"):
        src = img.get("src")
        if not isinstance(src, str) or not src.strip():
            resource = img.get("resource")
            if isinstance(resource, str) and resource.strip():
                img["src"] = _absolute_media_url(resource)
            else:
                srcset = img.get("srcset")
                if isinstance(srcset, str):
                    first = srcset.split(",")[0].strip().split()
                    if first:
                        img["src"] = _absolute_media_url(first[0])
        else:
            img["src"] = _absolute_media_url(src)

        srcset = img.get("srcset")
        if isinstance(srcset, str):
            img["srcset"] = _rewrite_srcset(srcset)

    for source in soup.find_all("source"):
        srcset = source.get("srcset")
        if isinstance(srcset, str):
            source["srcset"] = _rewrite_srcset(srcset)


def _sanitize_images_for_display(soup: BeautifulSoup) -> None:
    """Remove intrinsic Wikipedia dimensions that break mobile HTML renderers."""
    for img in soup.find_all("img"):
        for attr in ("width", "height"):
            if attr in img.attrs:
                del img[attr]


def _rewrite_srcset(srcset: str) -> str:
    parts: list[str] = []
    for chunk in srcset.split(","):
        chunk = chunk.strip()
        if not chunk:
            continue
        tokens = chunk.split()
        if not tokens:
            continue
        tokens[0] = _absolute_media_url(tokens[0])
        parts.append(" ".join(tokens))
    return ", ".join(parts)


def _absolute_media_url(url: str) -> str:
    cleaned = url.strip()
    if cleaned.startswith("//"):
        return f"https:{cleaned}"
    if cleaned.startswith("/"):
        return f"{_WIKI_SITE}{cleaned}"
    if cleaned.startswith("./"):
        path = unquote(cleaned[2:]).replace(" ", "_")
        if path.startswith("File:"):
            filename = path[len("File:") :]
            return f"{_COMMONS_FILE_PATH}{quote(filename, safe='')}"
        return f"{_WIKI_SITE}/wiki/{path}"
    return cleaned


def _remove_reader_mode_chrome(soup: BeautifulSoup) -> None:
    for selector in _READER_MODE_SELECTORS:
        for node in soup.select(selector):
            node.decompose()

    for heading in soup.find_all(["h2", "h3"]):
        heading_id = _heading_section_id(heading)
        if heading_id not in _SECTION_HEADING_IDS:
            continue
        section_nodes = [heading]
        sibling = heading.find_next_sibling()
        while sibling is not None and sibling.name not in ("h2", "h3"):
            section_nodes.append(sibling)
            sibling = sibling.find_next_sibling()
        for node in section_nodes:
            node.decompose()


def _heading_section_id(heading) -> str:
    attrs = heading.attrs
    heading_id = ""
    if attrs is not None:
        heading_id = str(attrs.get("id") or "")
    span = heading.find("span", class_="mw-headline")
    if span is not None:
        span_attrs = span.attrs
        if span_attrs is not None and span_attrs.get("id"):
            heading_id = str(span_attrs["id"])
    return heading_id.lower()


def prepare_article_for_display(html: str | None) -> str | None:
    """Strip Wikipedia chrome and rewrite media URLs for in-app reading."""
    if not html or not html.strip():
        return None
    soup = BeautifulSoup(html, "html.parser")
    _rewrite_links(soup, f"{_WIKI_SITE}/wiki/")
    _rewrite_media_urls(soup)
    _sanitize_images_for_display(soup)
    _remove_reader_mode_chrome(soup)
    body = soup.body if soup.body is not None else soup
    rendered = body.decode_contents().strip()
    return rendered or None


def parse_article_html(html: str) -> ParsedArticle:
    """Extract dinosaur fields from full Parsoid HTML."""
    soup = BeautifulSoup(html, "html.parser")
    infobox_html = _extract_infobox_text(html)
    infobox_text = _infobox_plain_text(soup)
    birth, death = _parse_ma_range(infobox_html, infobox_text)
    period = _parse_period(infobox_html, infobox_text)
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
