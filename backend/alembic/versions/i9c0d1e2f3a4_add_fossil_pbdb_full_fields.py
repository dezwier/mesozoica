"""add fossil pbdb full fields

Revision ID: i9c0d1e2f3a4
Revises: h8b9c0d1e2f3
Create Date: 2026-07-12 09:55:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "i9c0d1e2f3a4"
down_revision: Union[str, None] = "h8b9c0d1e2f3"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("fossil", sa.Column("identified_rank", sa.String(length=50), nullable=True))
    op.add_column("fossil", sa.Column("accepted_name", sa.String(length=255), nullable=True))
    op.add_column("fossil", sa.Column("accepted_no", sa.Integer(), nullable=True))
    op.add_column("fossil", sa.Column("accepted_rank", sa.String(length=50), nullable=True))
    op.add_column("fossil", sa.Column("accepted_attr", sa.String(length=255), nullable=True))
    op.add_column("fossil", sa.Column("genus", sa.String(length=100), nullable=True))
    op.add_column("fossil", sa.Column("taxon_order", sa.String(length=100), nullable=True))
    op.add_column("fossil", sa.Column("taxon_class", sa.String(length=100), nullable=True))
    op.add_column("fossil", sa.Column("phylum", sa.String(length=100), nullable=True))
    op.add_column("fossil", sa.Column("geogcomments", sa.Text(), nullable=True))
    op.add_column("fossil", sa.Column("geogscale", sa.String(length=100), nullable=True))
    op.add_column("fossil", sa.Column("geoplate", sa.Integer(), nullable=True))
    op.add_column("fossil", sa.Column("latlng_basis", sa.String(length=100), nullable=True))
    op.add_column("fossil", sa.Column("latlng_precision", sa.Integer(), nullable=True))
    op.add_column("fossil", sa.Column("paleolat", sa.Numeric(9, 6), nullable=True))
    op.add_column("fossil", sa.Column("paleolng", sa.Numeric(9, 6), nullable=True))
    op.add_column("fossil", sa.Column("paleomodel", sa.String(length=50), nullable=True))
    op.add_column("fossil", sa.Column("paleoage", sa.String(length=50), nullable=True))
    op.add_column("fossil", sa.Column("stratscale", sa.String(length=100), nullable=True))
    op.add_column("fossil", sa.Column("lithology1", sa.String(length=100), nullable=True))
    op.add_column("fossil", sa.Column("lithadj1", sa.String(length=100), nullable=True))
    op.add_column("fossil", sa.Column("concentration", sa.String(length=100), nullable=True))
    op.add_column("fossil", sa.Column("temporal_resolution", sa.String(length=100), nullable=True))
    op.add_column("fossil", sa.Column("collection_aka", sa.String(length=255), nullable=True))
    op.add_column("fossil", sa.Column("collection_no", sa.Integer(), nullable=True))
    op.add_column("fossil", sa.Column("collection_methods", sa.Text(), nullable=True))
    op.add_column("fossil", sa.Column("research_group", sa.String(length=100), nullable=True))
    op.add_column("fossil", sa.Column("fossilsfrom1", sa.String(length=10), nullable=True))
    op.add_column("fossil", sa.Column("size_classes", sa.String(length=100), nullable=True))
    op.add_column("fossil", sa.Column("record_type", sa.String(length=20), nullable=True))
    op.add_column("fossil", sa.Column("diet", sa.String(length=100), nullable=True))
    op.add_column("fossil", sa.Column("environment", sa.String(length=255), nullable=True))
    op.add_column("fossil", sa.Column("taxon_environment", sa.String(length=100), nullable=True))
    op.add_column("fossil", sa.Column("life_habit", sa.String(length=255), nullable=True))
    op.add_column("fossil", sa.Column("motility", sa.String(length=100), nullable=True))
    op.add_column("fossil", sa.Column("reproduction", sa.String(length=255), nullable=True))
    op.add_column("fossil", sa.Column("ontogeny", sa.String(length=255), nullable=True))
    op.add_column("fossil", sa.Column("reference_no", sa.Integer(), nullable=True))
    op.add_column("fossil", sa.Column("ref_author", sa.String(length=255), nullable=True))
    op.add_column("fossil", sa.Column("ref_pubyr", sa.Integer(), nullable=True))
    op.add_column("fossil", sa.Column("reid_no", sa.Integer(), nullable=True))
    op.alter_column("fossil", "pres_mode", type_=sa.String(length=100), existing_type=sa.String(length=50))


def downgrade() -> None:
    op.alter_column("fossil", "pres_mode", type_=sa.String(length=50), existing_type=sa.String(length=100))
    op.drop_column("fossil", "reid_no")
    op.drop_column("fossil", "ref_pubyr")
    op.drop_column("fossil", "ref_author")
    op.drop_column("fossil", "reference_no")
    op.drop_column("fossil", "ontogeny")
    op.drop_column("fossil", "reproduction")
    op.drop_column("fossil", "motility")
    op.drop_column("fossil", "life_habit")
    op.drop_column("fossil", "taxon_environment")
    op.drop_column("fossil", "environment")
    op.drop_column("fossil", "diet")
    op.drop_column("fossil", "record_type")
    op.drop_column("fossil", "size_classes")
    op.drop_column("fossil", "fossilsfrom1")
    op.drop_column("fossil", "research_group")
    op.drop_column("fossil", "collection_methods")
    op.drop_column("fossil", "collection_no")
    op.drop_column("fossil", "collection_aka")
    op.drop_column("fossil", "temporal_resolution")
    op.drop_column("fossil", "concentration")
    op.drop_column("fossil", "lithadj1")
    op.drop_column("fossil", "lithology1")
    op.drop_column("fossil", "stratscale")
    op.drop_column("fossil", "paleoage")
    op.drop_column("fossil", "paleomodel")
    op.drop_column("fossil", "paleolng")
    op.drop_column("fossil", "paleolat")
    op.drop_column("fossil", "latlng_precision")
    op.drop_column("fossil", "latlng_basis")
    op.drop_column("fossil", "geoplate")
    op.drop_column("fossil", "geogscale")
    op.drop_column("fossil", "geogcomments")
    op.drop_column("fossil", "phylum")
    op.drop_column("fossil", "taxon_class")
    op.drop_column("fossil", "taxon_order")
    op.drop_column("fossil", "genus")
    op.drop_column("fossil", "accepted_attr")
    op.drop_column("fossil", "accepted_rank")
    op.drop_column("fossil", "accepted_no")
    op.drop_column("fossil", "accepted_name")
    op.drop_column("fossil", "identified_rank")
