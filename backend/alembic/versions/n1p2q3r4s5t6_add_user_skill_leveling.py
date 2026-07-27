"""add user skill leveling columns and backfill

Revision ID: n1p2q3r4s5t6
Revises: m0n1o2p3q4r5
Create Date: 2026-07-27 10:20:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlmodel import Session

revision: str = "n1p2q3r4s5t6"
down_revision: Union[str, None] = "m0n1o2p3q4r5"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_COLUMNS = (
    ("exploration_xp", sa.Integer(), 0),
    ("excavation_xp", sa.Integer(), 0),
    ("research_xp", sa.Integer(), 0),
    ("xp_from_sites", sa.Integer(), 0),
    ("xp_from_fossils", sa.Integer(), 0),
    ("xp_from_active_distance", sa.Integer(), 0),
    ("xp_from_passive_distance", sa.Integer(), 0),
)


def upgrade() -> None:
    for name, col_type, default in _COLUMNS:
        op.add_column(
            "user",
            sa.Column(
                name, col_type, nullable=False, server_default=sa.text(str(default))
            ),
        )

    from app.core.database import engine
    from app.services.level_service import backfill_all_users

    with Session(engine) as session:
        backfill_all_users(session)

    for name, _, _ in _COLUMNS:
        op.alter_column("user", name, server_default=None)


def downgrade() -> None:
    for name, _, _ in reversed(_COLUMNS):
        op.drop_column("user", name)
