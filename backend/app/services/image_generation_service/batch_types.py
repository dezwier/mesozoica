"""Shared batch counters/summary types for curated image generation jobs."""

from __future__ import annotations

from dataclasses import dataclass, field

GENERATION_ATTEMPTS = 3
GENERATION_RETRY_BACKOFF_SECONDS = 1.0


@dataclass
class GenerateCounters:
    generated: int = 0
    skipped: int = 0
    failed: int = 0


@dataclass
class GenerateSummary:
    total_candidates: int
    skipped_existing: int
    counters: GenerateCounters = field(default_factory=GenerateCounters)
    dry_run: bool = False
    elapsed_s: float = 0.0
    cost_usd: float = 0.0
    output_dir: str = ""
    version: str = "v1"


def generate_exit_code(summary: GenerateSummary) -> int:
    if summary.counters.failed == 0:
        return 0
    attempted = summary.counters.generated + summary.counters.failed
    if attempted == 0:
        return 0
    return 1 if summary.counters.failed / attempted > 0.10 else 0
