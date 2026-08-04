"""Editorial metadata for the game config control board.

Separate from ``game_config.py`` (which owns parsing and validation) because
this describes *who may edit what* rather than *what is a valid value*. The
future admin web app reads this via ``GET /admin/game-config/schema``.
"""

from __future__ import annotations

from dataclasses import dataclass

from app.core.game_config import DOCUMENT_FILES


@dataclass(frozen=True)
class GameConfigDocSpec:
    doc_id: str
    filename: str
    label: str
    is_skill: bool


def _label(doc_id: str) -> str:
    return doc_id.replace("_", " ").title()


DOCUMENT_SPECS: tuple[GameConfigDocSpec, ...] = tuple(
    GameConfigDocSpec(
        doc_id=doc_id,
        filename=filename,
        label=_label(doc_id),
        is_skill=filename[0].isdigit(),
    )
    for doc_id, filename in DOCUMENT_FILES
)

# Slash-separated paths the admin write API refuses to change. '*' matches one
# path segment. Classification is path-level, not document-level, because
# leveling.yaml and tool_actions.yaml both mix tunable knobs with content.
LOCKED_PATHS: tuple[str, ...] = (
    # Skill ids are keys inside User.skill_xp / User.skill_breakdown JSON.
    # Renaming one silently orphans every player's XP.
    "leveling/skills",
    # 99 content strings, not knobs.
    "leveling/career_titles",
    # Palettes — visual identity, and the client bundles matching assets.
    "period_colors",
    "rock_type_colors",
    # Player-facing prose on tool cards.
    "tool_actions/*/stats_explanation",
)
