"""Request/response DTOs for the game config control board. Owned by the game_config feature."""

from __future__ import annotations

from datetime import datetime
from typing import Any, Literal, Optional

from pydantic import BaseModel, Field

# Documents are served as the raw parsed YAML shape (not ``model_dump``) so the
# Flutter parsers, which are written against that shape, need no changes.
Documents = dict[str, dict[str, Any]]


class GameConfigVersionResponse(BaseModel):
    version: int
    checksum: str
    activated_at: Optional[datetime] = None


class GameConfigResponse(BaseModel):
    version: int
    checksum: str
    activated_at: Optional[datetime] = None
    source: Literal["db", "yaml", "db-stale"] = "db"
    documents: Documents


class GameConfigRevisionSummary(BaseModel):
    version: int
    checksum: str
    source: str
    note: str
    created_at: datetime
    created_by_user_id: Optional[int] = None
    is_active: bool


class GameConfigDocMeta(BaseModel):
    doc_id: str
    filename: str
    label: str
    is_skill: bool


class GameConfigSchemaResponse(BaseModel):
    """Editorial metadata for the future admin web app."""

    documents: list[GameConfigDocMeta]
    locked_paths: list[str]


class GameConfigPublishRequest(BaseModel):
    documents: Documents
    base_version: Optional[int] = Field(
        default=None,
        description="Version this edit started from; omit to skip conflict checking.",
    )
    note: str = ""


class GameConfigDocumentPatchRequest(BaseModel):
    data: dict[str, Any]
    base_version: Optional[int] = None
    note: str = ""


class GameConfigRollbackRequest(BaseModel):
    to_version: int
    note: str = ""


class GameConfigValidateResponse(BaseModel):
    valid: bool
    errors: list[dict[str, Any]] = Field(default_factory=list)
