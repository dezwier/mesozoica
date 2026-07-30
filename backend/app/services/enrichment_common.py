"""Shared batch types/helpers for LLM enrichment jobs."""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class EnrichCounters:
    enriched: int = 0
    skipped: int = 0
    failed: int = 0


@dataclass
class EnrichSummary:
    total_candidates: int
    counters: EnrichCounters = field(default_factory=EnrichCounters)
    dry_run: bool = False
    overwrite: bool = False
    elapsed_s: float = 0.0

    @property
    def failure_rate(self) -> float:
        attempted = self.counters.enriched + self.counters.failed
        if attempted == 0:
            return 0.0
        return self.counters.failed / attempted


def enrich_exit_code(summary: EnrichSummary, *, failure_threshold: float) -> int:
    """Return non-zero if failure rate exceeds ``failure_threshold``."""
    if summary.counters.failed == 0:
        return 0
    if summary.failure_rate > failure_threshold:
        return 1
    return 0
