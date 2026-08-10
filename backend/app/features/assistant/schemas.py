"""Field-assistant request/response models."""

from pydantic import BaseModel, Field


class AskRequest(BaseModel):
    question: str = Field(min_length=1, max_length=500)


class SourceLink(BaseModel):
    title: str
    url: str
    kind: str = Field(description="Source kind, e.g. wikipedia or openalex")


class AskResponse(BaseModel):
    answer: str
    sources: list[SourceLink]
