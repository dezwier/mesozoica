"""Backfill field site.version to Summer 26 when created on/after its run_date.

Revision ID: h7i8j9k0l1m2
Revises: g6h7i8j9k0l1
Create Date: 2026-08-04 10:00:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "h7i8j9k0l1m2"
down_revision: Union[str, None] = "g6h7i8j9k0l1"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

# Matches images/site-types/Summer 26/meta.yaml run_date.
_SUMMER_26 = "Summer 26"
_ORIGINAL = "Original"
_SUMMER_26_RUN_DATE = "2026-07-29T00:00:00+00:00"


def upgrade() -> None:
    # Field sites stamped Original by field-generate when the worker had no
    # curated-image volume (latest_* fell back to Original). Re-label those
    # created on/after Summer 26's run_date.
    op.execute(
        sa.text(
            """
            UPDATE site
            SET version = :summer
            WHERE data_source = 'field'
              AND version = :original
              AND created_at IS NOT NULL
              AND created_at >= CAST(:run_date AS timestamptz)
            """
        ).bindparams(
            summer=_SUMMER_26,
            original=_ORIGINAL,
            run_date=_SUMMER_26_RUN_DATE,
        )
    )


def downgrade() -> None:
    op.execute(
        sa.text(
            """
            UPDATE site
            SET version = :original
            WHERE data_source = 'field'
              AND version = :summer
              AND created_at IS NOT NULL
              AND created_at >= CAST(:run_date AS timestamptz)
            """
        ).bindparams(
            summer=_SUMMER_26,
            original=_ORIGINAL,
            run_date=_SUMMER_26_RUN_DATE,
        )
    )
