"""Generic resume loop for durable checkpointed work units."""

from __future__ import annotations

import logging
from collections.abc import Callable
from typing import Literal, Protocol, TypeVar

from mesozoica_ai.common.errors import AiError

logger = logging.getLogger(__name__)

T = TypeVar("T")
Outcome = Literal["skipped", "succeeded", "failed"]


class UnitOfWork(Protocol):
    """Minimal persistence surface used by resumable jobs."""

    def save(self, item: object) -> None:
        """Stage one mutated item for persistence."""

    def commit(self) -> None:
        """Commit the current unit of work."""

    def rollback(self) -> None:
        """Roll back the current unit of work after failure."""


def run_resumable_item(
    work_unit: UnitOfWork,
    item: T,
    *,
    should_run: Callable[[T], bool],
    begin: Callable[[T], None],
    work: Callable[[T], None],
    complete: Callable[[T], None],
    fail: Callable[[T, BaseException], None],
    reload: Callable[[T], T],
    label: str,
    reraise: Callable[[BaseException], bool] | None = None,
) -> Outcome:
    """Run one checkpointed unit: begin → commit → work → complete/fail → commit."""
    if not should_run(item):
        return "skipped"
    begin(item)
    work_unit.save(item)
    work_unit.commit()
    try:
        work(item)
        complete(item)
        outcome: Outcome = "succeeded"
    except Exception as exc:
        work_unit.rollback()
        item = reload(item)
        fail(item, exc)
        outcome = "failed"
        if isinstance(exc, AiError):
            logger.warning("%s failed: %s", label, exc)
        else:
            logger.exception("%s failed", label)
        work_unit.save(item)
        work_unit.commit()
        if reraise is not None and reraise(exc):
            raise
        return outcome
    work_unit.save(item)
    work_unit.commit()
    return outcome
