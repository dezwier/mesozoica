"""add fossil pbdb remaining fields

Revision ID: q7j8e9f0g1h2
Revises: p6i7d8e9f0g1
Create Date: 2026-07-14 08:50:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "q7j8e9f0g1h2"
down_revision: Union[str, None] = "p6i7d8e9f0g1"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("fossil", sa.Column("identified_no", sa.Integer(), nullable=True))
    op.add_column("fossil", sa.Column("taxon_difference", sa.String(length=100), nullable=True))
    op.add_column("fossil", sa.Column("county", sa.String(length=100), nullable=True))
    op.add_column("fossil", sa.Column("altitude_value", sa.Numeric(9, 2), nullable=True))
    op.add_column("fossil", sa.Column("altitude_unit", sa.String(length=50), nullable=True))
    op.add_column("fossil", sa.Column("protected", sa.String(length=20), nullable=True))
    op.add_column("fossil", sa.Column("geological_group", sa.String(length=255), nullable=True))
    op.add_column("fossil", sa.Column("geological_member", sa.String(length=255), nullable=True))
    op.add_column("fossil", sa.Column("strat_zone", sa.String(length=100), nullable=True))
    op.add_column("fossil", sa.Column("localsection", sa.String(length=255), nullable=True))
    op.add_column("fossil", sa.Column("localbed", sa.String(length=255), nullable=True))
    op.add_column("fossil", sa.Column("localbedunit", sa.String(length=100), nullable=True))
    op.add_column("fossil", sa.Column("localorder", sa.String(length=50), nullable=True))
    op.add_column("fossil", sa.Column("regionalsection", sa.String(length=255), nullable=True))
    op.add_column("fossil", sa.Column("regionalbed", sa.String(length=255), nullable=True))
    op.add_column("fossil", sa.Column("regionalbedunit", sa.String(length=100), nullable=True))
    op.add_column("fossil", sa.Column("regionalorder", sa.String(length=50), nullable=True))
    op.add_column("fossil", sa.Column("late_interval", sa.String(length=100), nullable=True))
    op.add_column("fossil", sa.Column("lithification1", sa.String(length=100), nullable=True))
    op.add_column("fossil", sa.Column("minor_lithology1", sa.String(length=100), nullable=True))
    op.add_column("fossil", sa.Column("lithology2", sa.String(length=100), nullable=True))
    op.add_column("fossil", sa.Column("lithadj2", sa.String(length=100), nullable=True))
    op.add_column("fossil", sa.Column("lithification2", sa.String(length=100), nullable=True))
    op.add_column("fossil", sa.Column("minor_lithology2", sa.String(length=100), nullable=True))
    op.add_column("fossil", sa.Column("fossilsfrom2", sa.String(length=10), nullable=True))
    op.add_column("fossil", sa.Column("collection_coverage", sa.String(length=100), nullable=True))
    op.add_column("fossil", sa.Column("collection_size", sa.String(length=100), nullable=True))
    op.add_column("fossil", sa.Column("rock_censused", sa.String(length=255), nullable=True))
    op.add_column("fossil", sa.Column("collection_comments", sa.Text(), nullable=True))
    op.add_column("fossil", sa.Column("taxonomy_comments", sa.Text(), nullable=True))
    op.add_column("fossil", sa.Column("thickness", sa.String(length=100), nullable=True))
    op.add_column("fossil", sa.Column("reinforcement", sa.String(length=100), nullable=True))
    op.add_column("fossil", sa.Column("plant_organ", sa.String(length=100), nullable=True))
    op.add_column("fossil", sa.Column("preservation_comments", sa.Text(), nullable=True))
    op.add_column("fossil", sa.Column("spatial_resolution", sa.String(length=100), nullable=True))
    op.add_column("fossil", sa.Column("lagerstatten", sa.String(length=100), nullable=True))
    op.add_column("fossil", sa.Column("orientation", sa.String(length=100), nullable=True))
    op.add_column("fossil", sa.Column("abund_in_sediment", sa.String(length=100), nullable=True))
    op.add_column("fossil", sa.Column("sorting", sa.String(length=100), nullable=True))
    op.add_column("fossil", sa.Column("bioerosion", sa.String(length=100), nullable=True))
    op.add_column("fossil", sa.Column("encrustation", sa.String(length=100), nullable=True))
    op.add_column("fossil", sa.Column("tectonic_setting", sa.String(length=100), nullable=True))
    op.add_column("fossil", sa.Column("geology_comments", sa.Text(), nullable=True))


def downgrade() -> None:
    op.drop_column("fossil", "geology_comments")
    op.drop_column("fossil", "tectonic_setting")
    op.drop_column("fossil", "encrustation")
    op.drop_column("fossil", "bioerosion")
    op.drop_column("fossil", "sorting")
    op.drop_column("fossil", "abund_in_sediment")
    op.drop_column("fossil", "orientation")
    op.drop_column("fossil", "lagerstatten")
    op.drop_column("fossil", "spatial_resolution")
    op.drop_column("fossil", "preservation_comments")
    op.drop_column("fossil", "plant_organ")
    op.drop_column("fossil", "reinforcement")
    op.drop_column("fossil", "thickness")
    op.drop_column("fossil", "taxonomy_comments")
    op.drop_column("fossil", "collection_comments")
    op.drop_column("fossil", "rock_censused")
    op.drop_column("fossil", "collection_size")
    op.drop_column("fossil", "collection_coverage")
    op.drop_column("fossil", "fossilsfrom2")
    op.drop_column("fossil", "minor_lithology2")
    op.drop_column("fossil", "lithification2")
    op.drop_column("fossil", "lithadj2")
    op.drop_column("fossil", "lithology2")
    op.drop_column("fossil", "minor_lithology1")
    op.drop_column("fossil", "lithification1")
    op.drop_column("fossil", "late_interval")
    op.drop_column("fossil", "regionalorder")
    op.drop_column("fossil", "regionalbedunit")
    op.drop_column("fossil", "regionalbed")
    op.drop_column("fossil", "regionalsection")
    op.drop_column("fossil", "localorder")
    op.drop_column("fossil", "localbedunit")
    op.drop_column("fossil", "localbed")
    op.drop_column("fossil", "localsection")
    op.drop_column("fossil", "strat_zone")
    op.drop_column("fossil", "geological_member")
    op.drop_column("fossil", "geological_group")
    op.drop_column("fossil", "protected")
    op.drop_column("fossil", "altitude_unit")
    op.drop_column("fossil", "altitude_value")
    op.drop_column("fossil", "county")
    op.drop_column("fossil", "taxon_difference")
    op.drop_column("fossil", "identified_no")
