"""rename formation_map_session to orbit_survey_session

Revision ID: x7y8z9a0b1c2
Revises: w6x7y8z9a0b1
Create Date: 2026-08-01 19:40:00.000000

"""

from typing import Sequence, Union

from alembic import op

revision: str = "x7y8z9a0b1c2"
down_revision: Union[str, None] = "w6x7y8z9a0b1"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.rename_table("formation_map_session", "orbit_survey_session")
    op.execute(
        "UPDATE orbit_survey_session SET action_key = 'orbit_survey' "
        "WHERE action_key = 'formation_map'"
    )
    # Rename indexes to match new table name (Postgres).
    for old, new in (
        ("ix_formation_map_session_user_id", "ix_orbit_survey_session_user_id"),
        ("ix_formation_map_session_action_key", "ix_orbit_survey_session_action_key"),
        ("ix_formation_map_session_status", "ix_orbit_survey_session_status"),
        ("ix_formation_map_session_expires_at", "ix_orbit_survey_session_expires_at"),
    ):
        op.execute(f'ALTER INDEX IF EXISTS "{old}" RENAME TO "{new}"')


def downgrade() -> None:
    op.execute(
        "UPDATE orbit_survey_session SET action_key = 'formation_map' "
        "WHERE action_key = 'orbit_survey'"
    )
    for old, new in (
        ("ix_orbit_survey_session_user_id", "ix_formation_map_session_user_id"),
        ("ix_orbit_survey_session_action_key", "ix_formation_map_session_action_key"),
        ("ix_orbit_survey_session_status", "ix_formation_map_session_status"),
        ("ix_orbit_survey_session_expires_at", "ix_formation_map_session_expires_at"),
    ):
        op.execute(f'ALTER INDEX IF EXISTS "{old}" RENAME TO "{new}"')
    op.rename_table("orbit_survey_session", "formation_map_session")
