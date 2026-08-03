"""rename site_survey skill keys to site_stewardship

Revision ID: d3e4f5a6b7c8
Revises: c2d3e4f5a6b7
Create Date: 2026-08-03 12:15:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "d3e4f5a6b7c8"
down_revision: Union[str, None] = "c2d3e4f5a6b7"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_OLD = "site_survey"
_NEW = "site_stewardship"


def _rename_json_key(column: str, *, old: str, new: str) -> None:
    """Rename a top-level JSON object key on \"user\".{column} (Postgres JSONB)."""
    op.execute(
        sa.text(
            f"""
            UPDATE "user"
            SET {column} = CASE
                WHEN {column} ? :new THEN {column} - :old
                ELSE ({column} - :old)
                     || jsonb_build_object(:new, {column}->:old)
            END
            WHERE {column} ? :old
            """
        ).bindparams(old=old, new=new)
    )


def upgrade() -> None:
    _rename_json_key("skill_xp", old=_OLD, new=_NEW)
    _rename_json_key("skill_breakdown", old=_OLD, new=_NEW)
    op.execute(
        sa.text(
            """
            UPDATE tool_type
            SET category = replace(category, :old, :new)
            WHERE category LIKE :pattern
            """
        ).bindparams(old=_OLD, new=_NEW, pattern=f"%{_OLD}%")
    )


def downgrade() -> None:
    _rename_json_key("skill_xp", old=_NEW, new=_OLD)
    _rename_json_key("skill_breakdown", old=_NEW, new=_OLD)
    op.execute(
        sa.text(
            """
            UPDATE tool_type
            SET category = replace(category, :old, :new)
            WHERE category LIKE :pattern
            """
        ).bindparams(old=_NEW, new=_OLD, pattern=f"%{_NEW}%")
    )
