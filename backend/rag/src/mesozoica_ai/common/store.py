"""Session unit-of-work adapter for checkpoint commits."""

from __future__ import annotations

from typing import Any


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
