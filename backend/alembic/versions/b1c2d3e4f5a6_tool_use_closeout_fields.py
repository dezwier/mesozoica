"""tool use closeout fields on sessions and missions

Revision ID: b1c2d3e4f5a6
Revises: a0b1c2d3e4f5
Create Date: 2026-08-02 10:10:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "b1c2d3e4f5a6"
down_revision: Union[str, None] = "a0b1c2d3e4f5"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_SESSION_TABLES = (
    "guidance_session",
    "orbit_survey_session",
    "formation_map_session",
    "terrain_echo_session",
)


def upgrade() -> None:
    for table in _SESSION_TABLES:
        op.add_column(table, sa.Column("ended_at", sa.DateTime(), nullable=True))
        op.add_column(table, sa.Column("used_duration_s", sa.Integer(), nullable=True))
        op.add_column(
            table, sa.Column("stop_reason", sa.String(length=16), nullable=True)
        )

    op.add_column("tool_mission", sa.Column("ended_at", sa.DateTime(), nullable=True))
    op.add_column(
        "tool_mission", sa.Column("used_duration_s", sa.Integer(), nullable=True)
    )
    op.add_column(
        "tool_mission", sa.Column("stop_reason", sa.String(length=16), nullable=True)
    )

    conn = op.get_bind()

    for table in _SESSION_TABLES:
        # Cancelled → manual; charge cancelled_at - started_at (fallback expires).
        conn.execute(
            sa.text(
                f"""
                UPDATE {table}
                SET
                  ended_at = COALESCE(cancelled_at, expires_at, updated_at),
                  used_duration_s = GREATEST(
                    0,
                    CAST(
                      EXTRACT(
                        EPOCH FROM (
                          COALESCE(cancelled_at, expires_at, updated_at) - started_at
                        )
                      ) AS INTEGER
                    )
                  ),
                  stop_reason = 'manual'
                WHERE status = 'cancelled'
                  AND used_duration_s IS NULL
                """
            )
        )
        # Expired → exhausted; charge full allocated window.
        conn.execute(
            sa.text(
                f"""
                UPDATE {table}
                SET
                  ended_at = COALESCE(expires_at, updated_at),
                  used_duration_s = GREATEST(
                    0,
                    CAST(
                      EXTRACT(
                        EPOCH FROM (COALESCE(expires_at, updated_at) - started_at)
                      ) AS INTEGER
                    )
                  ),
                  stop_reason = 'exhausted'
                WHERE status = 'expired'
                  AND used_duration_s IS NULL
                """
            )
        )

    # Aerial: cancelled → manual (elapsed flight or 0 if never took off).
    conn.execute(
        sa.text(
            """
            UPDATE tool_mission
            SET
              ended_at = COALESCE(flight_ends_at, updated_at),
              used_duration_s = CASE
                WHEN flight_started_at IS NULL THEN 0
                ELSE GREATEST(
                  0,
                  CAST(
                    EXTRACT(
                      EPOCH FROM (
                        COALESCE(flight_ends_at, updated_at) - flight_started_at
                      )
                    ) AS INTEGER
                  )
                )
              END,
              stop_reason = 'manual'
            WHERE status = 'cancelled'
              AND used_duration_s IS NULL
            """
        )
    )
    # Done → exhausted; charge planned flight duration.
    conn.execute(
        sa.text(
            """
            UPDATE tool_mission
            SET
              ended_at = COALESCE(flight_ends_at, updated_at),
              used_duration_s = GREATEST(0, flight_duration_s),
              stop_reason = 'exhausted'
            WHERE status = 'done'
              AND used_duration_s IS NULL
            """
        )
    )
    # Failed → failed; charge elapsed flight or 0.
    conn.execute(
        sa.text(
            """
            UPDATE tool_mission
            SET
              ended_at = COALESCE(flight_ends_at, updated_at),
              used_duration_s = CASE
                WHEN flight_started_at IS NULL THEN 0
                ELSE GREATEST(
                  0,
                  CAST(
                    EXTRACT(
                      EPOCH FROM (
                        COALESCE(flight_ends_at, updated_at) - flight_started_at
                      )
                    ) AS INTEGER
                  )
                )
              END,
              stop_reason = 'failed'
            WHERE status = 'failed'
              AND used_duration_s IS NULL
            """
        )
    )


def downgrade() -> None:
    op.drop_column("tool_mission", "stop_reason")
    op.drop_column("tool_mission", "used_duration_s")
    op.drop_column("tool_mission", "ended_at")
    for table in _SESSION_TABLES:
        op.drop_column(table, "stop_reason")
        op.drop_column(table, "used_duration_s")
        op.drop_column(table, "ended_at")
