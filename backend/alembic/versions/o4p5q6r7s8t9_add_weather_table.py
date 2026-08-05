"""add weather table for hourly past + forecast per cell

Revision ID: o4p5q6r7s8t9
Revises: n3o4p5q6r7s8
Create Date: 2026-08-05 13:50:00.000000

"""

from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "o4p5q6r7s8t9"
down_revision: Union[str, None] = "n3o4p5q6r7s8"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "weather",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("cell_i", sa.Integer(), nullable=False),
        sa.Column("cell_j", sa.Integer(), nullable=False),
        sa.Column("center_lat", sa.Float(), nullable=False),
        sa.Column("center_lon", sa.Float(), nullable=False),
        sa.Column("valid_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("is_forecast", sa.Boolean(), nullable=False),
        sa.Column("weather_type", sa.String(length=32), nullable=False),
        sa.Column("temperature_c", sa.Float(), nullable=False),
        sa.Column("wmo_code", sa.Integer(), nullable=False),
        sa.Column("fetched_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "cell_i", "cell_j", "valid_at", name="uq_weather_cell_valid_at"
        ),
    )
    op.create_index("ix_weather_cell_i", "weather", ["cell_i"])
    op.create_index("ix_weather_cell_j", "weather", ["cell_j"])
    op.create_index("ix_weather_valid_at", "weather", ["valid_at"])
    op.create_index(
        "ix_weather_cell_i_cell_j_valid_at",
        "weather",
        ["cell_i", "cell_j", "valid_at"],
    )


def downgrade() -> None:
    op.drop_index("ix_weather_cell_i_cell_j_valid_at", table_name="weather")
    op.drop_index("ix_weather_valid_at", table_name="weather")
    op.drop_index("ix_weather_cell_j", table_name="weather")
    op.drop_index("ix_weather_cell_i", table_name="weather")
    op.drop_table("weather")
