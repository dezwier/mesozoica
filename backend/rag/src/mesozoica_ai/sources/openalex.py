"""OpenAlex GROBID full-text retrieval with scholarly provenance."""

from __future__ import annotations

import hashlib
import html
import logging
import re
import xml.etree.ElementTree as ET
from collections.abc import Mapping
from datetime import date, datetime, time, timezone
from typing import Any

from pydantic import SecretStr

from mesozoica_ai.common.errors import RateLimitedError, SourceFetchError
from mesozoica_ai.common.models import Document as SourceDocument
from mesozoica_ai.sources.helpers import with_metadata
from mesozoica_ai.sources.http import RetryingJsonClient

logger = logging.getLogger(__name__)

API_URL = "https://api.openalex.org/works"
CONTENT_URL = "https://content.openalex.org/works/{work_id}.grobid-xml"
_SKIPPED_SECTION_TYPES = frozenset({
    "references", "bibliography", "acknowledgement", "acknowledgements",
    "acknowledgment", "funding", "annex", "footnote",
})
_SKIPPED_HEADINGS = frozenset({
    "references", "bibliography", "acknowledgements", "acknowledgment",
    "acknowledgement", "funding", "notes", "further reading", "see also",
})


def retrieve_openalex(
    query: str,
    *,
    user_agent: str,
    api_key: str | SecretStr,
    limit: int = 10,
    exclude_work_ids: set[str] | frozenset[str] | None = None,
    timeout: float | None = None,
    metadata: Mapping[str, Any] | None = None,
) -> list[SourceDocument]:
    """Fetch OpenAlex works as GROBID TEI section documents.

    ``limit`` is the number of *new* papers to collect (after exclusions).
    Already-known OpenAlex work IDs can be passed in ``exclude_work_ids``.
    """
    try:
        documents = _retrieve_documents(
            query,
            api_key=api_key,
            user_agent=user_agent,
            limit=limit,
            exclude_work_ids=exclude_work_ids or frozenset(),
            timeout=timeout,
        )
    except RateLimitedError as exc:
        if not exc.partial_documents:
            raise
        raise RateLimitedError(
            exc.source,
            retry_after=exc.retry_after,
            partial_documents=with_metadata(exc.partial_documents, metadata),
        ) from exc
    return with_metadata(documents, metadata)


def paper_inventory(documents: list[Any]) -> list[tuple[str, str]]:
    """Return unique (work_id, title) pairs in first-seen order from stored docs."""
    seen: set[str] = set()
    papers: list[tuple[str, str]] = []
    for document in documents:
        if hasattr(document, "metadata"):
            meta = document.metadata
            work_id = str(getattr(meta, "source_id", "") or "").strip()
            title = str(getattr(meta, "title", "") or "").strip()
        else:
            meta = (document or {}).get("metadata") or {}
            work_id = str(meta.get("source_id") or "").strip()
            title = str(meta.get("title") or "").strip()
        if not work_id or work_id in seen:
            continue
        seen.add(work_id)
        papers.append((work_id, title or work_id))
    return papers


_ITALIC_BLOCK_RE = re.compile(
    r"<(?:i|em|italic)(?:\s[^>]*)?>(.*?)</(?:i|em|italic)>",
    re.IGNORECASE | re.DOTALL,
)
_TAG_RE = re.compile(r"<[^>]+>")
_WS_RE = re.compile(r"\s+")


def _display_title(title: str) -> str:
    """Unescape and keep italics as ``<i>…</i>`` for downstream display."""
    text = html.unescape(title or "")
    protected: list[str] = []

    def _protect(match: re.Match[str]) -> str:
        inner = _WS_RE.sub(" ", match.group(1)).strip()
        protected.append(inner)
        return f"\0I{len(protected) - 1}\0"

    text = _ITALIC_BLOCK_RE.sub(_protect, text)
    text = _TAG_RE.sub(" ", text)
    text = _WS_RE.sub(" ", text).strip()

    def _restore(match: re.Match[str]) -> str:
        idx = int(match.group(1))
        inner = protected[idx] if 0 <= idx < len(protected) else ""
        return f"<i>{inner}</i>" if inner else ""

    text = re.sub(r"\0I(\d+)\0", _restore, text)
    text = re.sub(r"(\S)<i>", r"\1 <i>", text)
    text = re.sub(r"</i>(\S)", r"</i> \1", text)
    return _WS_RE.sub(" ", text).strip()


def _retrieve_documents(
    query: str,
    *,
    api_key: str | SecretStr,
    user_agent: str,
    limit: int = 10,
    exclude_work_ids: set[str] | frozenset[str] = frozenset(),
    timeout: float | None = None,
) -> list[SourceDocument]:
    key = api_key.get_secret_value() if isinstance(api_key, SecretStr) else api_key
    if not key.strip():
        raise ValueError("OPENALEX_API_KEY is required")
    if not user_agent.strip():
        raise ValueError("OpenAlex requires a descriptive user agent")
    client_options = {} if timeout is None else {
        "connect_timeout_seconds": timeout,
        "read_timeout_seconds": timeout,
    }
    with RetryingJsonClient(**client_options) as client:
        return _retrieve(
            query,
            api_key=key,
            user_agent=user_agent,
            limit=limit,
            exclude_work_ids=set(exclude_work_ids),
            client=client,
        )


def _retrieve(
    query: str,
    *,
    api_key: str,
    user_agent: str,
    limit: int,
    exclude_work_ids: set[str],
    client: RetryingJsonClient,
) -> list[SourceDocument]:
    if not query.strip():
        raise ValueError("OpenAlex query must not be blank")
    if not 1 <= limit <= 100:
        raise ValueError("OpenAlex limit must be between 1 and 100")
    # Pull a wider relevance-ranked pool so exclusions / TEI failures can be topped up.
    candidate_pool = min(100, max(limit * 3, limit + len(exclude_work_ids), 20))
    payload = client.get(
        API_URL,
        params={
            "api_key": api_key,
            "search": f'"{query.strip()}"',
            "filter": (
                "is_retracted:false,has_content.grobid_xml:true,type:article|preprint"
            ),
            "per_page": candidate_pool,
            "sort": "relevance_score:desc",
        },
        headers={"User-Agent": user_agent},
        source="openalex",
    )
    documents: list[SourceDocument] = []
    collected: set[str] = set()
    for work in payload.get("results", []):
        if len(collected) >= limit:
            break
        if work.get("is_retracted"):
            continue
        work_id = str(work.get("id") or "").rsplit("/", 1)[-1]
        title = str(work.get("display_name") or work.get("title") or "").strip()
        if not work_id or not title:
            continue
        display_title = _display_title(title)
        if work_id in exclude_work_ids or work_id in collected:
            logger.debug("OpenAlex already have %s  %s", work_id, display_title)
            continue
        try:
            sections = _fulltext_sections(
                work_id, api_key=api_key, user_agent=user_agent, client=client
            )
        except RateLimitedError as exc:
            raise RateLimitedError(
                exc.source,
                retry_after=exc.retry_after,
                partial_documents=documents,
            ) from exc
        except (SourceFetchError, ET.ParseError) as exc:
            logger.debug(
                "OpenAlex TEI skip %s  %s (%s)", work_id, display_title, exc
            )
            continue
        if not sections:
            logger.debug("OpenAlex TEI empty %s  %s", work_id, display_title)
            continue
        logger.debug(
            "OpenAlex + %s  %s (%s sections)",
            work_id,
            display_title,
            len(sections),
        )
        documents.extend(
            _section_documents(
                work_id=work_id,
                sections=sections,
                base_metadata=_work_metadata(work, work_id=work_id, title=display_title),
            )
        )
        collected.add(work_id)
    if not documents:
        logger.info(
            "OpenAlex: no usable GROBID TEI for query %r (candidates checked)",
            query,
        )
    return documents


def _fulltext_sections(
    work_id: str,
    *,
    api_key: str,
    user_agent: str,
    client: RetryingJsonClient,
) -> list[tuple[str, int, list[str], str]]:
    tei = client.get_text(
        CONTENT_URL.format(work_id=work_id),
        params={"api_key": api_key},
        headers={"User-Agent": user_agent, "Accept": "application/xml"},
        source="openalex-content",
    )
    return parse_tei_sections(tei)


def _section_documents(
    *,
    work_id: str,
    sections: list[tuple[str, int, list[str], str]],
    base_metadata: dict[str, Any],
) -> list[SourceDocument]:
    documents: list[SourceDocument] = []
    for ordinal, (heading, depth, path, text) in enumerate(sections):
        if not text.strip():
            continue
        documents.append(SourceDocument(
            id=_section_document_id(work_id, ordinal, heading),
            text=text,
            metadata={
                **base_metadata,
                "section": heading,
                "section_path": path,
                "section_depth": depth,
                "section_ordinal": ordinal,
                "content_format": "grobid_xml",
                "provenance": "OpenAlex GROBID TEI",
            },
        ))
    return documents


_DOCUMENT_ID_MAX_LEN = 512


def _section_document_id(work_id: str, ordinal: int, heading: str) -> str:
    """Build a stable section id that fits dinosaur_knowledge_doc.document_id."""
    slug = _slug(heading)
    base = f"openalex:{work_id}:section:{ordinal}:"
    budget = _DOCUMENT_ID_MAX_LEN - len(base)
    if budget <= 0:
        return f"openalex:{work_id}:section:{ordinal}"[:_DOCUMENT_ID_MAX_LEN]
    if len(slug) <= budget:
        return base + slug
    digest = hashlib.sha256(slug.encode()).hexdigest()[:10]
    keep = max(0, budget - len(digest) - 1)
    return f"{base}{slug[:keep]}-{digest}"


def _work_metadata(work: dict[str, Any], *, work_id: str, title: str) -> dict[str, Any]:
    authors = [
        str(item.get("author", {}).get("display_name"))
        for item in work.get("authorships", [])
        if item.get("author", {}).get("display_name")
    ]
    source = (work.get("primary_location") or {}).get("source") or {}
    best_location = work.get("best_oa_location") or {}
    content_urls = work.get("content_urls") or {}
    return {
        "source": "openalex",
        "source_id": work_id,
        "title": title,
        "source_url": work.get("doi") or content_urls.get("grobid_xml") or work.get("id"),
        "published_at": _as_datetime(work.get("publication_date")),
        "updated_at": _as_datetime(work.get("updated_date")),
        "source_version": work.get("updated_date"),
        "doi": work.get("doi"),
        "authors": authors,
        "publication_year": work.get("publication_year"),
        "venue": source.get("display_name"),
        "cited_by_count": work.get("cited_by_count", 0),
        "relevance_score": work.get("relevance_score"),
        "license": best_location.get("license"),
    }


def parse_tei_sections(xml_text: str) -> list[tuple[str, int, list[str], str]]:
    """Return (heading, depth, path, text) tuples with paragraph breaks preserved."""
    stripped = xml_text.lstrip()
    if not stripped.startswith("<"):
        raise ET.ParseError("TEI payload is not XML")
    root = ET.fromstring(xml_text)
    sections: list[tuple[str, int, list[str], str]] = []

    abstract = _first_text(_find(root, "abstract"))
    if abstract:
        sections.append(("Abstract", 0, ["Abstract"], abstract))

    body = _find(root, "body")
    if body is not None:
        lead = _direct_paragraphs(body)
        if lead:
            sections.append(("Body", 0, ["Body"], lead))
        _walk_divs(body, path=[], sections=sections)
    return sections


def _walk_divs(
    parent: ET.Element,
    *,
    path: list[str],
    sections: list[tuple[str, int, list[str], str]],
) -> None:
    for child in parent:
        if _local(child.tag) != "div":
            continue
        div_type = (child.get("type") or "").casefold()
        if div_type in _SKIPPED_SECTION_TYPES:
            continue
        heading = _heading(child) or (div_type.title() if div_type else "Section")
        if heading.casefold() in _SKIPPED_HEADINGS:
            continue
        section_path = [*path, heading]
        text = _direct_paragraphs(child)
        if text:
            sections.append((heading, len(section_path) - 1, section_path, text))
        _walk_divs(child, path=section_path, sections=sections)


def _heading(div: ET.Element) -> str:
    for child in div:
        if _local(child.tag) == "head":
            return _normalize_ws("".join(child.itertext()))
    return ""


def _direct_paragraphs(parent: ET.Element) -> str:
    parts: list[str] = []
    for child in parent:
        local = _local(child.tag)
        if local in {"p", "formula"}:
            text = _normalize_ws("".join(child.itertext()))
            if text:
                parts.append(text)
    return "\n\n".join(parts)


def _first_text(element: ET.Element | None) -> str:
    if element is None:
        return ""
    paragraphs = _direct_paragraphs(element)
    if paragraphs:
        return paragraphs
    return _normalize_ws("".join(element.itertext()))


def _find(root: ET.Element, local_name: str) -> ET.Element | None:
    for element in root.iter():
        if _local(element.tag) == local_name:
            return element
    return None


def _local(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def _normalize_ws(value: str) -> str:
    return re.sub(r"[ \t]+", " ", value).strip()


def _slug(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", value.casefold()).strip("-") or "section"


def _as_datetime(value: Any) -> datetime | None:
    if not value:
        return None
    raw = str(value).replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(raw)
    except ValueError:
        try:
            parsed = datetime.combine(date.fromisoformat(raw), time.min)
        except ValueError:
            return None
    return parsed.replace(tzinfo=timezone.utc) if parsed.tzinfo is None else parsed
