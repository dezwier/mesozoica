"""rename tool→tool_type, add tool instances, reshape user_tool

Revision ID: p8q9r0s1t2u3
Revises: o7p8q9r0s1t2
Create Date: 2026-07-28 10:30:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "p8q9r0s1t2u3"
down_revision: Union[str, None] = "o7p8q9r0s1t2"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _drop_fks_to_table(table_name: str, referred_table: str) -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    for fk in inspector.get_foreign_keys(table_name):
        if fk.get("referred_table") == referred_table and fk.get("name"):
            op.drop_constraint(fk["name"], table_name, type_="foreignkey")


def upgrade() -> None:
    _drop_fks_to_table("user_tool", "tool")
    _drop_fks_to_table("tool_mission", "tool")
    _drop_fks_to_table("guidance_session", "tool")

    op.rename_table("tool", "tool_type")
    op.execute(
        sa.text("ALTER INDEX IF EXISTS ix_tool_name RENAME TO ix_tool_type_name")
    )

    op.create_table(
        "tool",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("tool_type_id", sa.Integer(), nullable=False),
        sa.Column(
            "spawn_date",
            sa.DateTime(timezone=True),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
        sa.Column("level", sa.Integer(), server_default="1", nullable=False),
        sa.ForeignKeyConstraint(
            ["tool_type_id"],
            ["tool_type.id"],
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_tool_tool_type_id", "tool", ["tool_type_id"])
    op.create_index("ix_tool_spawn_date", "tool", ["spawn_date"])

    # Map each legacy ownership row to a new tool instance.
    op.execute(
        sa.text(
            """
            CREATE TEMP TABLE _tool_instance_map (
                user_id INTEGER NOT NULL,
                old_tool_id INTEGER NOT NULL,
                new_tool_id INTEGER NOT NULL,
                PRIMARY KEY (user_id, old_tool_id)
            )
            """
        )
    )

    connection = op.get_bind()
    legacy_rows = connection.execute(
        sa.text(
            "SELECT id, user_id, tool_id, level, timestamp FROM user_tool ORDER BY id"
        )
    ).fetchall()
    for row in legacy_rows:
        new_id = connection.execute(
            sa.text(
                """
                INSERT INTO tool (tool_type_id, spawn_date, level)
                VALUES (:tool_type_id, :spawn_date, :level)
                RETURNING id
                """
            ),
            {
                "tool_type_id": row.tool_id,
                "spawn_date": row.timestamp,
                "level": row.level,
            },
        ).scalar_one()
        connection.execute(
            sa.text(
                """
                INSERT INTO _tool_instance_map (user_id, old_tool_id, new_tool_id)
                VALUES (:user_id, :old_tool_id, :new_tool_id)
                """
            ),
            {
                "user_id": row.user_id,
                "old_tool_id": row.tool_id,
                "new_tool_id": new_id,
            },
        )

    op.execute(
        sa.text(
            """
            UPDATE user_tool AS ut
            SET tool_id = m.new_tool_id
            FROM _tool_instance_map AS m
            WHERE ut.user_id = m.user_id AND ut.tool_id = m.old_tool_id
            """
        )
    )

    orphan_missions = connection.execute(
        sa.text(
            """
            SELECT tm.id, tm.user_id, tm.tool_id
            FROM tool_mission AS tm
            LEFT JOIN _tool_instance_map AS m
              ON m.user_id = tm.user_id AND m.old_tool_id = tm.tool_id
            WHERE m.new_tool_id IS NULL
            """
        )
    ).fetchall()
    if orphan_missions:
        raise RuntimeError(
            f"tool_mission rows without ownership map: {orphan_missions!r}"
        )
    op.execute(
        sa.text(
            """
            UPDATE tool_mission AS tm
            SET tool_id = m.new_tool_id
            FROM _tool_instance_map AS m
            WHERE tm.user_id = m.user_id AND tm.tool_id = m.old_tool_id
            """
        )
    )

    orphan_sessions = connection.execute(
        sa.text(
            """
            SELECT gs.id, gs.user_id, gs.tool_id
            FROM guidance_session AS gs
            LEFT JOIN _tool_instance_map AS m
              ON m.user_id = gs.user_id AND m.old_tool_id = gs.tool_id
            WHERE m.new_tool_id IS NULL
            """
        )
    ).fetchall()
    if orphan_sessions:
        raise RuntimeError(
            f"guidance_session rows without ownership map: {orphan_sessions!r}"
        )
    op.execute(
        sa.text(
            """
            UPDATE guidance_session AS gs
            SET tool_id = m.new_tool_id
            FROM _tool_instance_map AS m
            WHERE gs.user_id = m.user_id AND gs.tool_id = m.old_tool_id
            """
        )
    )

    op.add_column(
        "user_tool",
        sa.Column(
            "action",
            sa.String(length=32),
            nullable=False,
            server_default="owned",
        ),
    )
    op.create_index("ix_user_tool_action", "user_tool", ["action"])

    op.drop_constraint("uq_user_tool_user_tool", "user_tool", type_="unique")
    op.drop_constraint("user_tool_pkey", "user_tool", type_="primary")
    op.drop_column("user_tool", "id")
    op.drop_column("user_tool", "level")
    op.create_primary_key(
        "pk_user_tool",
        "user_tool",
        ["user_id", "tool_id", "timestamp"],
    )

    op.create_foreign_key(
        "fk_user_tool_tool_id",
        "user_tool",
        "tool",
        ["tool_id"],
        ["id"],
        ondelete="CASCADE",
    )
    op.create_foreign_key(
        "fk_tool_mission_tool_id",
        "tool_mission",
        "tool",
        ["tool_id"],
        ["id"],
    )
    op.create_foreign_key(
        "fk_guidance_session_tool_id",
        "guidance_session",
        "tool",
        ["tool_id"],
        ["id"],
    )

    op.execute(sa.text("DROP TABLE IF EXISTS _tool_instance_map"))


def downgrade() -> None:
    _drop_fks_to_table("user_tool", "tool")
    _drop_fks_to_table("tool_mission", "tool")
    _drop_fks_to_table("guidance_session", "tool")

    connection = op.get_bind()

    # Restore catalog ids on missions/sessions before reshaping user_tool.
    op.execute(
        sa.text(
            """
            UPDATE tool_mission AS tm
            SET tool_id = t.tool_type_id
            FROM tool AS t
            WHERE tm.tool_id = t.id
            """
        )
    )
    op.execute(
        sa.text(
            """
            UPDATE guidance_session AS gs
            SET tool_id = t.tool_type_id
            FROM tool AS t
            WHERE gs.tool_id = t.id
            """
        )
    )

    # Rebuild legacy user_tool from owned events + instance rows.
    op.execute(sa.text("ALTER TABLE user_tool RENAME TO user_tool_events"))
    op.create_table(
        "user_tool",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("tool_id", sa.Integer(), nullable=False),
        sa.Column("level", sa.Integer(), server_default="1", nullable=False),
        sa.Column(
            "timestamp",
            sa.DateTime(timezone=True),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["user_id"], ["user.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", "tool_id", name="uq_user_tool_user_tool"),
    )
    op.create_index("ix_user_tool_user_id", "user_tool", ["user_id"])
    op.create_index("ix_user_tool_tool_id", "user_tool", ["tool_id"])
    op.create_index("ix_user_tool_timestamp", "user_tool", ["timestamp"])

    op.execute(
        sa.text(
            """
            INSERT INTO user_tool (user_id, tool_id, level, timestamp)
            SELECT
                e.user_id,
                t.tool_type_id,
                t.level,
                e.timestamp
            FROM user_tool_events AS e
            JOIN tool AS t ON t.id = e.tool_id
            WHERE e.action = 'owned'
            """
        )
    )
    op.drop_table("user_tool_events")

    op.drop_index("ix_tool_spawn_date", table_name="tool")
    op.drop_index("ix_tool_tool_type_id", table_name="tool")
    op.drop_table("tool")

    op.rename_table("tool_type", "tool")
    op.execute(
        sa.text("ALTER INDEX IF EXISTS ix_tool_type_name RENAME TO ix_tool_name")
    )

    op.create_foreign_key(
        "fk_user_tool_tool_id",
        "user_tool",
        "tool",
        ["tool_id"],
        ["id"],
        ondelete="CASCADE",
    )
    op.create_foreign_key(
        "fk_tool_mission_tool_id",
        "tool_mission",
        "tool",
        ["tool_id"],
        ["id"],
    )
    op.create_foreign_key(
        "fk_guidance_session_tool_id",
        "guidance_session",
        "tool",
        ["tool_id"],
        ["id"],
    )
