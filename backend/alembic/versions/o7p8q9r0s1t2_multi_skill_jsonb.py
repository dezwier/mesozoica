"""migrate user skill xp to jsonb multi-skill storage

Revision ID: o7p8q9r0s1t2
Revises: n1p2q3r4s5t6
Create Date: 2026-07-27 12:00:00.000000

"""

import json
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlmodel import Session, select

revision: str = "o7p8q9r0s1t2"
down_revision: Union[str, None] = "n1p2q3r4s5t6"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_LEGACY_COLUMNS = (
    "exploration_xp",
    "excavation_xp",
    "research_xp",
    "xp_from_sites",
    "xp_from_fossils",
    "xp_from_active_distance",
    "xp_from_passive_distance",
)


def upgrade() -> None:
    with op.get_context().autocommit_block():
        op.execute(
            sa.text(
                'ALTER TABLE "user" ADD COLUMN IF NOT EXISTS skill_xp JSONB '
                "DEFAULT '{}'::jsonb NOT NULL"
            )
        )
        op.execute(
            sa.text(
                'ALTER TABLE "user" ADD COLUMN IF NOT EXISTS skill_breakdown JSONB '
                "DEFAULT '{}'::jsonb NOT NULL"
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
        for name in _LEGACY_COLUMNS:
            op.execute(sa.text(f'ALTER TABLE "user" DROP COLUMN IF EXISTS {name}'))
        op.execute(sa.text('ALTER TABLE "user" ALTER COLUMN skill_xp DROP DEFAULT'))
        op.execute(
            sa.text('ALTER TABLE "user" ALTER COLUMN skill_breakdown DROP DEFAULT')
        )


def downgrade() -> None:
    with op.get_context().autocommit_block():
        for name in _LEGACY_COLUMNS:
            op.execute(
                sa.text(
                    f'ALTER TABLE "user" ADD COLUMN IF NOT EXISTS '
                    f"{name} INTEGER DEFAULT 0 NOT NULL"
                )
            )
        op.execute(sa.text('ALTER TABLE "user" DROP COLUMN IF EXISTS skill_xp'))
        op.execute(sa.text('ALTER TABLE "user" DROP COLUMN IF EXISTS skill_breakdown'))
