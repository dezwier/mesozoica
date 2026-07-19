"""seed user id 1 as admin

Revision ID: a7t8u9v0w1x2
Revises: z6s7l8m9n0o1
Create Date: 2026-07-19 16:40:00.000000

"""

from typing import Sequence, Union

from alembic import op

revision: str = "a7t8u9v0w1x2"
down_revision: Union[str, None] = "z6s7l8m9n0o1"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute('UPDATE "user" SET is_admin = true WHERE id = 1')


def downgrade() -> None:
    op.execute('UPDATE "user" SET is_admin = false WHERE id = 1')
