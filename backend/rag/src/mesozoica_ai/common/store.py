"""Persistence protocol for durable knowledge checkpoints."""

from __future__ import annotations

from typing import Any, Protocol, runtime_checkable

from mesozoica_ai.common.resume import UnitOfWork


@runtime_checkable
class SnapshotStore(Protocol):
    """Persistence surface used by acquire / index / evaluate / status flows."""

    def work_unit(self) -> UnitOfWork:
        """Return a unit of work bound to this store's session."""

    def get_or_create(self, subject: Any, source: str) -> Any:
        """Load or insert the checkpoint for one subject/source pair."""

    def reload(self, row: Any) -> Any:
        """Reload one checkpoint after a failed unit of work."""

    def list_indexable(
        self,
        *,
        names: list[str] | None = None,
        sources: list[str] | None = None,
        max_items: int | None = None,
    ) -> list[Any]:
        """Return acquired snapshots eligible for indexing."""

    def list_succeeded(self) -> list[Any]:
        """Return all successfully acquired snapshots."""

    def list_all(self, *, names: list[str] | None = None) -> list[Any]:
        """Return checkpoints for status display."""


class SessionUnitOfWork:
    """Adapt any session with add/commit/rollback to UnitOfWork."""

    def __init__(self, session: Any) -> None:
        self._session = session

    def save(self, item: object) -> None:
        self._session.add(item)

    def commit(self) -> None:
        self._session.commit()

    def rollback(self) -> None:
        self._session.rollback()
