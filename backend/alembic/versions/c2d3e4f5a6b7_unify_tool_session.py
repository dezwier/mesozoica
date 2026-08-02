"""unify tool_session and tool_session_event

Revision ID: c2d3e4f5a6b7
Revises: b1c2d3e4f5a6
Create Date: 2026-08-02 12:50:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import JSONB

revision: str = "c2d3e4f5a6b7"
down_revision: Union[str, None] = "b1c2d3e4f5a6"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

# Prefer JSONB on Postgres; JSON elsewhere.
_JSON = JSONB().with_variant(sa.JSON(), "sqlite")


def upgrade() -> None:
    op.create_table(
        "tool_session",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("user.id"), nullable=False),
        sa.Column("tool_id", sa.Integer(), sa.ForeignKey("tool.id"), nullable=False),
        sa.Column("action_key", sa.String(length=64), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("started_at", sa.DateTime(), nullable=False),
        sa.Column("expires_at", sa.DateTime(), nullable=True),
        sa.Column("ended_at", sa.DateTime(), nullable=True),
        sa.Column("used_duration_s", sa.Integer(), nullable=True),
        sa.Column("stop_reason", sa.String(length=16), nullable=True),
        sa.Column("params_json", _JSON, nullable=False),
        sa.Column("state_json", _JSON, nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
    )
    op.create_index("ix_tool_session_user_id", "tool_session", ["user_id"])
    op.create_index("ix_tool_session_tool_id", "tool_session", ["tool_id"])
    op.create_index("ix_tool_session_action_key", "tool_session", ["action_key"])
    op.create_index("ix_tool_session_status", "tool_session", ["status"])
    op.create_index("ix_tool_session_expires_at", "tool_session", ["expires_at"])

    op.create_table(
        "tool_session_event",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column(
            "session_id",
            sa.Integer(),
            sa.ForeignKey("tool_session.id"),
            nullable=False,
        ),
        sa.Column("event_type", sa.String(length=32), nullable=False),
        sa.Column(
            "site_id", sa.Integer(), sa.ForeignKey("site.site_id"), nullable=True
        ),
        sa.Column("due_at", sa.DateTime(), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("lat", sa.Float(), nullable=True),
        sa.Column("lon", sa.Float(), nullable=True),
        sa.Column("payload_json", _JSON, nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("processed_at", sa.DateTime(), nullable=True),
    )
    op.create_index(
        "ix_tool_session_event_session_id", "tool_session_event", ["session_id"]
    )
    op.create_index("ix_tool_session_event_due_at", "tool_session_event", ["due_at"])
    op.create_index("ix_tool_session_event_status", "tool_session_event", ["status"])

    # Mapping tables for id remaps (legacy id → new session id).
    op.create_table(
        "_ts_map",
        sa.Column("source", sa.String(length=32), nullable=False),
        sa.Column("legacy_id", sa.Integer(), nullable=False),
        sa.Column("session_id", sa.Integer(), nullable=False),
        sa.PrimaryKeyConstraint("source", "legacy_id"),
    )

    conn = op.get_bind()

    # --- timed sessions ---
    _migrate_guidance(conn)
    _migrate_orbit(conn)
    _migrate_formation(conn)
    _migrate_terrain(conn)
    _migrate_missions(conn)
    _migrate_events(conn)

    # user_site.source_mission_id → source_session_id
    op.add_column(
        "user_site",
        sa.Column("source_session_id", sa.Integer(), nullable=True),
    )
    conn.execute(
        sa.text(
            """
            UPDATE user_site AS us
            SET source_session_id = m.session_id
            FROM _ts_map AS m
            WHERE m.source = 'tool_mission'
              AND us.source_mission_id = m.legacy_id
            """
        )
    )
    # SQLite may not support FROM in UPDATE — fallback handled below if needed.
    op.drop_constraint(
        "fk_user_site_source_mission_id", "user_site", type_="foreignkey"
    )
    op.drop_index(
        op.f("ix_user_site_source_mission_id"), table_name="user_site"
    )
    op.drop_column("user_site", "source_mission_id")
    op.create_foreign_key(
        "user_site_source_session_id_fkey",
        "user_site",
        "tool_session",
        ["source_session_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_index(
        "ix_user_site_source_session_id", "user_site", ["source_session_id"]
    )

    op.drop_table("_ts_map")

    for table in (
        "tool_mission_event",
        "tool_mission",
        "guidance_session",
        "orbit_survey_session",
        "formation_map_session",
        "terrain_echo_session",
    ):
        op.drop_table(table)


def _status_timed(raw: str) -> str:
    if raw == "expired":
        return "completed"
    if raw == "cancelled":
        return "cancelled"
    if raw == "active":
        return "active"
    return raw


def _status_mission(raw: str) -> str:
    return {
        "ensuring": "pending",
        "flying": "active",
        "done": "completed",
        "failed": "failed",
        "cancelled": "cancelled",
    }.get(raw, raw)


def _migrate_guidance(conn) -> None:
    rows = conn.execute(sa.text("SELECT * FROM guidance_session")).mappings().all()
    for row in rows:
        params = {
            "duration_minutes": row["duration_minutes"],
            "discovery_chance": row["discovery_chance"],
            "direction_exactness": row["direction_exactness"],
            "distance_exactness": row["distance_exactness"],
        }
        params = {k: v for k, v in params.items() if v is not None}
        new_id = _insert_session(
            conn,
            user_id=row["user_id"],
            tool_id=row["tool_id"],
            action_key=row["action_key"],
            status=_status_timed(row["status"]),
            started_at=row["started_at"],
            expires_at=row["expires_at"],
            ended_at=row["ended_at"],
            used_duration_s=row["used_duration_s"],
            stop_reason=row["stop_reason"],
            params=params,
            state={},
            created_at=row["created_at"],
            updated_at=row["updated_at"],
        )
        conn.execute(
            sa.text(
                "INSERT INTO _ts_map (source, legacy_id, session_id) "
                "VALUES ('guidance_session', :lid, :sid)"
            ),
            {"lid": row["id"], "sid": new_id},
        )


def _migrate_orbit(conn) -> None:
    rows = conn.execute(sa.text("SELECT * FROM orbit_survey_session")).mappings().all()
    for row in rows:
        params = {
            "duration_minutes": row["duration_minutes"],
            "accuracy": row["accuracy"],
            "range": row["range"],
            "min_range_m": row["min_range_m"],
            "max_range_m": row["max_range_m"],
        }
        new_id = _insert_session(
            conn,
            user_id=row["user_id"],
            tool_id=row["tool_id"],
            action_key=row["action_key"],
            status=_status_timed(row["status"]),
            started_at=row["started_at"],
            expires_at=row["expires_at"],
            ended_at=row["ended_at"],
            used_duration_s=row["used_duration_s"],
            stop_reason=row["stop_reason"],
            params=params,
            state={},
            created_at=row["created_at"],
            updated_at=row["updated_at"],
        )
        conn.execute(
            sa.text(
                "INSERT INTO _ts_map (source, legacy_id, session_id) "
                "VALUES ('orbit_survey_session', :lid, :sid)"
            ),
            {"lid": row["id"], "sid": new_id},
        )


def _migrate_formation(conn) -> None:
    rows = conn.execute(sa.text("SELECT * FROM formation_map_session")).mappings().all()
    for row in rows:
        params = {
            "duration_minutes": row["duration_minutes"],
            "accuracy": row["accuracy"],
            "wideness_m": row["wideness_m"],
            "cell_size_m": row["cell_size_m"],
            "center_lat": row["center_lat"],
            "center_lon": row["center_lon"],
        }
        new_id = _insert_session(
            conn,
            user_id=row["user_id"],
            tool_id=row["tool_id"],
            action_key=row["action_key"],
            status=_status_timed(row["status"]),
            started_at=row["started_at"],
            expires_at=row["expires_at"],
            ended_at=row["ended_at"],
            used_duration_s=row["used_duration_s"],
            stop_reason=row["stop_reason"],
            params=params,
            state={},
            created_at=row["created_at"],
            updated_at=row["updated_at"],
        )
        conn.execute(
            sa.text(
                "INSERT INTO _ts_map (source, legacy_id, session_id) "
                "VALUES ('formation_map_session', :lid, :sid)"
            ),
            {"lid": row["id"], "sid": new_id},
        )


def _migrate_terrain(conn) -> None:
    rows = conn.execute(sa.text("SELECT * FROM terrain_echo_session")).mappings().all()
    for row in rows:
        params = {
            "duration_minutes": row["duration_minutes"],
            "accuracy": row["accuracy"],
            "range_m": row["range_m"],
        }
        new_id = _insert_session(
            conn,
            user_id=row["user_id"],
            tool_id=row["tool_id"],
            action_key=row["action_key"],
            status=_status_timed(row["status"]),
            started_at=row["started_at"],
            expires_at=row["expires_at"],
            ended_at=row["ended_at"],
            used_duration_s=row["used_duration_s"],
            stop_reason=row["stop_reason"],
            params=params,
            state={},
            created_at=row["created_at"],
            updated_at=row["updated_at"],
        )
        conn.execute(
            sa.text(
                "INSERT INTO _ts_map (source, legacy_id, session_id) "
                "VALUES ('terrain_echo_session', :lid, :sid)"
            ),
            {"lid": row["id"], "sid": new_id},
        )


def _migrate_missions(conn) -> None:
    import json

    rows = conn.execute(sa.text("SELECT * FROM tool_mission")).mappings().all()
    for row in rows:
        params = {
            k: row[k]
            for k in (
                "flight_speed_kmh",
                "max_route_km",
                "discovery_chance",
                "discovery_distance_m",
            )
            if row[k] is not None
        }
        try:
            route = json.loads(row["route_json"])
        except Exception:
            route = []
        try:
            ensure_ids = (
                json.loads(row["ensure_job_ids_json"])
                if row["ensure_job_ids_json"]
                else []
            )
        except Exception:
            ensure_ids = []
        state = {
            "route": route,
            "route_length_km": row["route_length_km"],
            "flight_duration_s": row["flight_duration_s"],
            "ensure_job_ids": ensure_ids,
        }
        if row["flight_started_at"] is not None:
            state["flight_started_at"] = row["flight_started_at"].isoformat()
        if row["flight_ends_at"] is not None:
            state["flight_ends_at"] = row["flight_ends_at"].isoformat()
        if row["error_message"]:
            state["error_message"] = row["error_message"]

        new_id = _insert_session(
            conn,
            user_id=row["user_id"],
            tool_id=row["tool_id"],
            action_key=row["action_key"],
            status=_status_mission(row["status"]),
            started_at=row["created_at"],
            expires_at=None,
            ended_at=row["ended_at"] or row["flight_ends_at"],
            used_duration_s=row["used_duration_s"],
            stop_reason=row["stop_reason"],
            params=params,
            state=state,
            created_at=row["created_at"],
            updated_at=row["updated_at"],
        )
        conn.execute(
            sa.text(
                "INSERT INTO _ts_map (source, legacy_id, session_id) "
                "VALUES ('tool_mission', :lid, :sid)"
            ),
            {"lid": row["id"], "sid": new_id},
        )


def _migrate_events(conn) -> None:
    rows = conn.execute(sa.text("SELECT * FROM tool_mission_event")).mappings().all()
    for row in rows:
        mapped = conn.execute(
            sa.text(
                "SELECT session_id FROM _ts_map "
                "WHERE source = 'tool_mission' AND legacy_id = :lid"
            ),
            {"lid": row["mission_id"]},
        ).scalar()
        if mapped is None:
            continue
        payload = {}
        if row["distance_along_km"] is not None:
            payload["distance_along_km"] = row["distance_along_km"]
        conn.execute(
            sa.text(
                """
                INSERT INTO tool_session_event (
                  session_id, event_type, site_id, due_at, status,
                  lat, lon, payload_json, created_at, processed_at
                ) VALUES (
                  :session_id, :event_type, :site_id, :due_at, :status,
                  :lat, :lon, CAST(:payload AS JSON), :created_at, :processed_at
                )
                """
            ),
            {
                "session_id": mapped,
                "event_type": row["event_type"],
                "site_id": row["site_id"],
                "due_at": row["due_at"],
                "status": row["status"],
                "lat": row["lat"],
                "lon": row["lon"],
                "payload": __import__("json").dumps(payload),
                "created_at": row["created_at"],
                "processed_at": row["processed_at"],
            },
        )


def _insert_session(
    conn,
    *,
    user_id,
    tool_id,
    action_key,
    status,
    started_at,
    expires_at,
    ended_at,
    used_duration_s,
    stop_reason,
    params,
    state,
    created_at,
    updated_at,
) -> int:
    import json

    result = conn.execute(
        sa.text(
            """
            INSERT INTO tool_session (
              user_id, tool_id, action_key, status, started_at, expires_at,
              ended_at, used_duration_s, stop_reason, params_json, state_json,
              created_at, updated_at
            ) VALUES (
              :user_id, :tool_id, :action_key, :status, :started_at, :expires_at,
              :ended_at, :used_duration_s, :stop_reason,
              CAST(:params AS JSON), CAST(:state AS JSON),
              :created_at, :updated_at
            )
            RETURNING id
            """
        ),
        {
            "user_id": user_id,
            "tool_id": tool_id,
            "action_key": action_key,
            "status": status,
            "started_at": started_at,
            "expires_at": expires_at,
            "ended_at": ended_at,
            "used_duration_s": used_duration_s,
            "stop_reason": stop_reason,
            "params": json.dumps(params),
            "state": json.dumps(state),
            "created_at": created_at,
            "updated_at": updated_at,
        },
    )
    return int(result.scalar())


def downgrade() -> None:
    raise NotImplementedError("Cannot downgrade unify_tool_session")
