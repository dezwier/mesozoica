"""add user skill leveling columns and backfill

Revision ID: n1p2q3r4s5t6
Revises: m0n1o2p3q4r5
Create Date: 2026-07-27 10:20:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlmodel import Session, select

revision: str = "n1p2q3r4s5t6"
down_revision: Union[str, None] = "m0n1o2p3q4r5"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_COLUMNS = (
    "exploration_xp",
    "excavation_xp",
    "research_xp",
    "xp_from_sites",
    "xp_from_fossils",
    "xp_from_active_distance",
    "xp_from_passive_distance",
)


def upgrade() -> None:
    # Commit DDL immediately so later SELECTs are not blocked by
    # AccessExclusiveLock held for the whole Alembic transaction.
    with op.get_context().autocommit_block():
        for name in _COLUMNS:
            op.execute(
                sa.text(
                    f'ALTER TABLE "user" ADD COLUMN IF NOT EXISTS '
                    f"{name} INTEGER DEFAULT 0 NOT NULL"
                )
            )

    from app.models.user import User
    from app.services.level_service.backfill import backfill_user_levels

    bind = op.get_bind()
    with Session(bind=bind) as session:
        for user in session.exec(select(User)).all():
            backfill_user_levels(session, user)
        session.flush()

    with op.get_context().autocommit_block():
        for name in _COLUMNS:
            op.execute(
                sa.text(f'ALTER TABLE "user" ALTER COLUMN {name} DROP DEFAULT')
            )


def downgrade() -> None:
    with op.get_context().autocommit_block():
        for name in reversed(_COLUMNS):
            op.execute(sa.text(f'ALTER TABLE "user" DROP COLUMN IF EXISTS {name}'))
