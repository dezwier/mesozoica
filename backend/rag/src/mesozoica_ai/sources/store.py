"""SQLModel SnapshotStore for checkpoint tables."""

from __future__ import annotations

from typing import Any

from mesozoica_ai.common.batch import DEFAULT_SUBJECT_KIND
from mesozoica_ai.common.resume import UnitOfWork
from mesozoica_ai.common.store import SessionUnitOfWork
from mesozoica_ai.sources import normalize_sources

SUCCEEDED = "succeeded"


class SqlSnapshotStore:
    """SQLModel SnapshotStore for a checkpoint table with the standard columns."""

    def __init__(
        self,
        session: Any,
        *,
        model: type[Any],
        subject_kind: str = DEFAULT_SUBJECT_KIND,
        succeeded_status: str = SUCCEEDED,
    ) -> None:
        self._session = session
        self._model = model
        self._subject_kind = subject_kind
        self._succeeded = succeeded_status

    def work_unit(self) -> UnitOfWork:
        return SessionUnitOfWork(self._session)

    def get_or_create(self, subject: Any, source: str) -> Any:
        from sqlmodel import select

        model = self._model
        snapshot = self._session.exec(
            select(model).where(
                model.subject_kind == self._subject_kind,
                model.subject_id == str(subject.id),
                model.source == source,
            )
        ).first()
        if snapshot is None:
            snapshot = model(
                subject_kind=self._subject_kind,
                subject_id=str(subject.id),
                subject_name=subject.name,
                source=source,
            )
            self._session.add(snapshot)
            self._session.commit()
            self._session.refresh(snapshot)
        elif snapshot.subject_name != subject.name:
            snapshot.subject_name = subject.name
        return snapshot

    def reload(self, row: Any) -> Any:
        snapshot = self._session.get(self._model, row.id)
        if snapshot is None:  # pragma: no cover - defensive
            raise RuntimeError(f"Missing knowledge snapshot after failure: {row.id}")
        return snapshot

    def list_indexable(
        self,
        *,
        names: list[str] | None = None,
        sources: list[str] | None = None,
        max_items: int | None = None,
    ) -> list[Any]:
        from sqlmodel import col, select

        model = self._model
        selected_sources = normalize_sources(sources)
        statement = (
            select(model)
            .where(
                model.subject_kind == self._subject_kind,
                model.acquisition_status == self._succeeded,
                col(model.source).in_(selected_sources),
            )
            .order_by(col(model.subject_name), col(model.source))
        )
        snapshots = list(self._session.exec(statement).all())
        return _filter_names(snapshots, names, max_items=max_items)

    def list_succeeded(self) -> list[Any]:
        from sqlmodel import select

        model = self._model
        return list(
            self._session.exec(
                select(model).where(
                    model.subject_kind == self._subject_kind,
                    model.acquisition_status == self._succeeded,
                )
            ).all()
        )

    def list_all(self, *, names: list[str] | None = None) -> list[Any]:
        from sqlmodel import col, select

        model = self._model
        rows = list(
            self._session.exec(
                select(model)
                .where(model.subject_kind == self._subject_kind)
                .order_by(col(model.subject_name), col(model.source))
            ).all()
        )
        return _filter_names(rows, names)


def _filter_names(
    rows: list[Any],
    names: list[str] | None,
    *,
    max_items: int | None = None,
) -> list[Any]:
    if names:
        wanted = {name.strip().casefold() for name in names if name.strip()}
        rows = [row for row in rows if row.subject_name.casefold() in wanted]
    if max_items is not None:
        rows = rows[:max_items]
    return rows
