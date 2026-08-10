"""Shared batch summary and subject scope helpers."""

from __future__ import annotations

from typing import Any

from pydantic import BaseModel

DEFAULT_NAMESPACE = "mesozoica"
DEFAULT_SUBJECT_KIND = "dinosaur"


class BatchSummary(BaseModel):
    """Aggregate outcome of a batch acquisition or indexing run."""

    candidates: int = 0
    succeeded: int = 0
    skipped: int = 0
    failed: int = 0

    @property
    def exit_code(self) -> int:
        return 1 if self.failed else 0

    def record(self, outcome: str) -> None:
        if outcome == "succeeded":
            self.succeeded += 1
        elif outcome == "failed":
            self.failed += 1
        else:
            self.skipped += 1

    def print_exit(self) -> int:
        """Print JSON summary and return the process exit code."""
        print(self.model_dump_json(indent=2))
        return self.exit_code


# Backward-compatible alias used by callers/tests.
JobSummary = BatchSummary


def subject_query(subject: Any, source: str) -> str:
    """Wikipedia title when present; otherwise the subject display name."""
    if source == "wikipedia":
        title = getattr(subject, "wikipedia_title", None)
        if title:
            return str(title)
    return str(subject.name)


def subject_metadata(
    subject: Any,
    _source: str,
    *,
    namespace: str = DEFAULT_NAMESPACE,
    subject_kind: str = DEFAULT_SUBJECT_KIND,
) -> dict[str, Any]:
    """Standard retrieval metadata for one subject."""
    return {
        "namespace": namespace,
        "subject_id": f"{subject_kind}:{subject.id}",
        "subject_name": subject.name,
    }


def snapshot_scope(
    snapshot: Any,
    *,
    namespace: str = DEFAULT_NAMESPACE,
    subject_kind: str = DEFAULT_SUBJECT_KIND,
) -> dict[str, Any]:
    """Azure filter scope for one acquired snapshot row."""
    return {
        "namespace": namespace,
        "subject_id": f"{subject_kind}:{snapshot.subject_id}",
        "source": snapshot.source,
    }
