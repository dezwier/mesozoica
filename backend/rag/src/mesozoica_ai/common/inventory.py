"""Summaries of acquired / embedded / indexed dinosaur knowledge."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from mesozoica_ai.common.batch import DEFAULT_SUBJECT_KIND
from mesozoica_ai.common.knowledge_repo import KnowledgeRepository
from mesozoica_ai.sources.openalex import paper_inventory


@dataclass(frozen=True)
class KnowledgeOverview:
    """Counts for one knowledge store (SQL snapshots or Azure chunks)."""

    dinosaurs: int
    wikipedia_dinos: int
    wikipedia_units: int
    openalex_dinos: int
    openalex_papers: int
    openalex_units: int
    unit_label: str = "sections"

    def summary_line(self) -> str:
        """One-line inventory suitable for script end logs."""
        return (
            f"{self.dinosaurs} dino(s) | "
            f"wiki {self.wikipedia_dinos} dino(s) / {self.wikipedia_units} {self.unit_label} | "
            f"openalex {self.openalex_dinos} dino(s) / {self.openalex_papers} paper(s) / "
            f"{self.openalex_units} {self.unit_label}"
        )

    def log_lines(self, *, title: str) -> list[str]:
        return [
            f"=== {title} ===",
            self.summary_line(),
        ]


def overview_drift_lines(
    left: KnowledgeOverview,
    right: KnowledgeOverview,
    *,
    left_name: str = "SQL",
    right_name: str = "Azure",
) -> list[str]:
    """Compare two overviews on dinosaurs/papers (unit counts may differ by design)."""
    lines = [f"=== Drift ({left_name} vs {right_name}) ==="]
    checks = [
        ("dinosaurs", left.dinosaurs, right.dinosaurs),
        ("wikipedia dinos", left.wikipedia_dinos, right.wikipedia_dinos),
        ("openalex dinos", left.openalex_dinos, right.openalex_dinos),
        ("openalex papers", left.openalex_papers, right.openalex_papers),
    ]
    drifted = False
    for label, a, b in checks:
        if a == b:
            lines.append(f"{label}: ok ({a})")
        else:
            drifted = True
            lines.append(f"{label}: {left_name}={a} {right_name}={b}")
    if not drifted:
        lines.append(
            f"note: {left.unit_label} vs {right.unit_label} counts may differ by design"
        )
    else:
        lines.append(
            f"{right_name} is behind {left_name} — re-ingest will sync missing papers/chunks"
        )
    return lines


def sql_knowledge_overview(
    repo: KnowledgeRepository,
    *,
    subject_kind: str = DEFAULT_SUBJECT_KIND,
) -> KnowledgeOverview:
    """Summarize acquired documents across succeeded sources."""
    subjects: set[str] = set()
    wiki_subjects: set[str] = set()
    openalex_subjects: set[str] = set()
    wiki_sections = 0
    openalex_sections = 0
    openalex_papers = 0

    for source_row in repo.list_sources(
        subject_kind=subject_kind, acquisition_succeeded_only=True
    ):
        subjects.add(str(source_row.subject_id))
        docs = repo.list_documents(source_row)
        if source_row.source == "wikipedia":
            wiki_subjects.add(str(source_row.subject_id))
            wiki_sections += len(docs)
        elif source_row.source == "openalex":
            openalex_subjects.add(str(source_row.subject_id))
            openalex_sections += len(docs)
            openalex_papers += len(paper_inventory(docs))

    return KnowledgeOverview(
        dinosaurs=len(subjects),
        wikipedia_dinos=len(wiki_subjects),
        wikipedia_units=wiki_sections,
        openalex_dinos=len(openalex_subjects),
        openalex_papers=openalex_papers,
        openalex_units=openalex_sections,
        unit_label="sections",
    )


def sql_embedded_overview(
    repo: KnowledgeRepository,
    *,
    subject_kind: str = DEFAULT_SUBJECT_KIND,
) -> KnowledgeOverview:
    """Summarize successfully embedded chunk rows."""
    subjects: set[str] = set()
    wiki_subjects: set[str] = set()
    openalex_subjects: set[str] = set()
    papers: set[tuple[str, str]] = set()
    wiki_chunks = 0
    openalex_chunks = 0

    for source_row in repo.list_sources(subject_kind=subject_kind):
        if source_row.embed_status != "succeeded":
            continue
        subject = str(source_row.subject_id)
        chunks = repo.list_chunks(source_row)
        subjects.add(subject)
        if source_row.source == "wikipedia":
            wiki_subjects.add(subject)
            wiki_chunks += len(chunks)
        elif source_row.source == "openalex":
            openalex_subjects.add(subject)
            openalex_chunks += len(chunks)
            for chunk in chunks:
                source_id = str(chunk.metadata.source_id or "").strip()
                if subject and source_id:
                    papers.add((subject, source_id))

    return KnowledgeOverview(
        dinosaurs=len(subjects),
        wikipedia_dinos=len(wiki_subjects),
        wikipedia_units=wiki_chunks,
        openalex_dinos=len(openalex_subjects),
        openalex_papers=len(papers),
        openalex_units=openalex_chunks,
        unit_label="chunks",
    )


def knowledge_overview_from_sql_rows(rows: list[Any]) -> KnowledgeOverview:
    """Compatibility helper for tests using fake document-bearing rows."""
    subjects: set[str] = set()
    wiki_subjects: set[str] = set()
    openalex_subjects: set[str] = set()
    wiki_sections = 0
    openalex_sections = 0
    openalex_papers = 0

    for row in rows:
        subjects.add(str(row.subject_id))
        docs = list(getattr(row, "documents", None) or [])
        if row.source == "wikipedia":
            wiki_subjects.add(str(row.subject_id))
            wiki_sections += len(docs)
        elif row.source == "openalex":
            openalex_subjects.add(str(row.subject_id))
            openalex_sections += len(docs)
            openalex_papers += len(paper_inventory(docs))

    return KnowledgeOverview(
        dinosaurs=len(subjects),
        wikipedia_dinos=len(wiki_subjects),
        wikipedia_units=wiki_sections,
        openalex_dinos=len(openalex_subjects),
        openalex_papers=openalex_papers,
        openalex_units=openalex_sections,
        unit_label="sections",
    )


def knowledge_overview_from_embedded_rows(rows: list[Any]) -> KnowledgeOverview:
    """Compatibility helper for tests using fake embedded_chunks rows."""
    subjects: set[str] = set()
    wiki_subjects: set[str] = set()
    openalex_subjects: set[str] = set()
    papers: set[tuple[str, str]] = set()
    wiki_chunks = 0
    openalex_chunks = 0

    for row in rows:
        subject = str(row.subject_id)
        source = str(row.source or "").casefold()
        chunks = list(getattr(row, "embedded_chunks", None) or [])
        subjects.add(subject)
        if source == "wikipedia":
            wiki_subjects.add(subject)
            wiki_chunks += len(chunks)
        elif source == "openalex":
            openalex_subjects.add(subject)
            openalex_chunks += len(chunks)
            for chunk in chunks:
                metadata = chunk.get("metadata") or {}
                source_id = str(metadata.get("source_id") or "").strip()
                if subject and source_id:
                    papers.add((subject, source_id))

    return KnowledgeOverview(
        dinosaurs=len(subjects),
        wikipedia_dinos=len(wiki_subjects),
        wikipedia_units=wiki_chunks,
        openalex_dinos=len(openalex_subjects),
        openalex_papers=len(papers),
        openalex_units=openalex_chunks,
        unit_label="chunks",
    )


def azure_knowledge_overview_from_rows(
    rows: list[dict[str, Any]],
) -> KnowledgeOverview:
    """Build an overview from Azure search hits (id/subject_id/source/source_id)."""
    subjects: set[str] = set()
    wiki_subjects: set[str] = set()
    openalex_subjects: set[str] = set()
    papers: set[tuple[str, str]] = set()
    wiki_chunks = 0
    openalex_chunks = 0

    for row in rows:
        subject = str(row.get("subject_id") or "").strip()
        source = str(row.get("source") or "").strip().casefold()
        source_id = str(row.get("source_id") or "").strip()
        if subject:
            subjects.add(subject)
        if source == "wikipedia":
            wiki_chunks += 1
            if subject:
                wiki_subjects.add(subject)
        elif source == "openalex":
            openalex_chunks += 1
            if subject:
                openalex_subjects.add(subject)
            if subject and source_id:
                papers.add((subject, source_id))

    return KnowledgeOverview(
        dinosaurs=len(subjects),
        wikipedia_dinos=len(wiki_subjects),
        wikipedia_units=wiki_chunks,
        openalex_dinos=len(openalex_subjects),
        openalex_papers=len(papers),
        openalex_units=openalex_chunks,
        unit_label="chunks",
    )
