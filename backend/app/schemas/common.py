"""Tiny shared response models."""

from pydantic import BaseModel


class OkResponse(BaseModel):
    """``{"ok": true}`` ack for mutation endpoints with no payload."""

    ok: bool = True
