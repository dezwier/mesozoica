"""Typed leveling document models."""

from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field, field_validator, model_validator

class LevelingSkillConfig(BaseModel):
    model_config = {"frozen": True}

    id: str
    name: str


class LevelingConfig(BaseModel):
    model_config = {"frozen": True}

    skills: tuple[LevelingSkillConfig, ...] = ()
    career_titles: tuple[str, ...] = ()

    @field_validator("skills", mode="before")
    @classmethod
    def _coerce_skills(cls, value: object) -> tuple[LevelingSkillConfig, ...]:
        if value is None:
            return ()
        if isinstance(value, (list, tuple)):
            return tuple(LevelingSkillConfig.model_validate(item) for item in value)
        raise ValueError("skills must be a sequence")

    @field_validator("career_titles", mode="before")
    @classmethod
    def _coerce_career_titles(cls, value: object) -> tuple[str, ...]:
        if value is None:
            return ()
        if isinstance(value, (list, tuple)):
            return tuple(str(item) for item in value)
        raise ValueError("career_titles must be a sequence of strings")

    @model_validator(mode="after")
    def _validate_leveling(self) -> LevelingConfig:
        if len(self.skills) < 1:
            raise ValueError("skills must have at least one entry")
        if len(self.career_titles) != 99:
            raise ValueError("career_titles must have exactly 99 entries")
        ids = [skill.id for skill in self.skills]
        if len(ids) != len(set(ids)):
            raise ValueError("skill ids must be unique")
        return self


