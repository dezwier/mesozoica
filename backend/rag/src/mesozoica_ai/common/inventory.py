"""Summaries of acquired / indexed dinosaur knowledge."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from mesozoica_ai.common.batch import DEFAULT_SUBJECT_KIND
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

    def log_lines(self, *, title: str) -> list[str]:
        return [
            f"=== {title} ===",
            f"dinosaurs: {self.dinosaurs}",
            (
                f"wikipedia: {self.wikipedia_dinos} dino(s), "
                f"{self.wikipedia_units} {self.unit_label}"
            ),
            (
                f"openalex:  {self.openalex_dinos} dino(s), "
                f"{self.openalex_papers} paper(s), "
                f"{self.openalex_units} {self.unit_label}"
            ),
        ]


def overview_drift_lines(
    sql: KnowledgeOverview, azure: KnowledgeOverview
) -> list[str]:
    """Compare SQL vs Azure on dinosaurs/papers (sections≠chunks by design)."""
    lines = ["=== Drift (SQL vs Azure) ==="]
    checks = [
        ("dinosaurs", sql.dinosaurs, azure.dinosaurs),
        ("wikipedia dinos", sql.wikipedia_dinos, azure.wikipedia_dinos),
        ("openalex dinos", sql.openalex_dinos, azure.openalex_dinos),
        ("openalex papers", sql.openalex_papers, azure.openalex_papers),
    ]
    drifted = False
    for label, left, right in checks:
        if left == right:
            lines.append(f"{label}: ok ({left})")
        else:
            drifted = True
            lines.append(f"{label}: SQL={left} Azure={right}")
    if not drifted:
        lines.append(
            "note: section vs chunk counts differ by design (chunking splits text)"
        )
    else:
        lines.append(
            "Azure is behind SQL — re-index will sync missing papers/chunks"
        )
    return lines


def sql_knowledge_overview(
    session: Any,
    model: type[Any],
    *,
    subject_kind: str = DEFAULT_SUBJECT_KIND,
    succeeded_only: bool = True,
) -> KnowledgeOverview:
    """Summarize ``dinosaur_knowledge`` rows (sections = stored documents)."""
    from sqlmodel import select

    statement = select(model).where(model.subject_kind == subject_kind)
    if succeeded_only:
        statement = statement.where(model.acquisition_status == "succeeded")
    return knowledge_overview_from_sql_rows(list(session.exec(statement).all()))


def knowledge_overview_from_sql_rows(rows: list[Any]) -> KnowledgeOverview:
    """Build a SQL overview from checkpoint rows."""
    subjects: set[str] = set()
    wiki_subjects: set[str] = set()
    openalex_subjects: set[str] = set()
    wiki_sections = 0
    openalex_sections = 0
    openalex_papers = 0

    for row in rows:
        subjects.add(str(row.subject_id))
        docs = list(row.documents or [])
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
