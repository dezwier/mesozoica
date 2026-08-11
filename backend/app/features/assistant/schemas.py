"""Field-assistant request/response models."""

from pydantic import BaseModel, Field


class AskRequest(BaseModel):
    question: str = Field(min_length=1, max_length=500)
    subject_id: str | None = Field(
        default=None,
        max_length=64,
        description="Optional dinosaur id to scope retrieval",
    )


class SourceLink(BaseModel):
    title: str
    url: str
    kind: str = Field(description="Source kind, e.g. wikipedia or openalex")


class AskResponse(BaseModel):
    answer: str
    sources: list[SourceLink]


class KnowledgeSubject(BaseModel):
    id: str
    name: str


class KnowledgeSubjectsResponse(BaseModel):
    subjects: list[KnowledgeSubject]


class KnowledgeSourceItem(BaseModel):
    title: str
    url: str
    kind: str


class KnowledgeSourceGroup(BaseModel):
    kind: str
    items: list[KnowledgeSourceItem]


class KnowledgeSourcesResponse(BaseModel):
    subject_id: str
    subject_name: str
    groups: list[KnowledgeSourceGroup]
