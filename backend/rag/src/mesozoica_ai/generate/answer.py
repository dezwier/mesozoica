"""Grounded Q&A over retrieved evidence (no application context)."""

from __future__ import annotations

import logging
from typing import Any

from pydantic import Field, field_validator

from mesozoica_ai.common.batch import DEFAULT_NAMESPACE, DEFAULT_SUBJECT_KIND
from mesozoica_ai.common.config import AiConfig
from mesozoica_ai.common.models import CitedOutput, RetrievalMode
from mesozoica_ai.generate.prompt import prompt_rag
from mesozoica_ai.index import embed_query, retrieve_chunks

logger = logging.getLogger(__name__)


def answer_from_index(
    output_model: type[Any],
    *,
    query: str,
    filters: dict[str, Any],
    config: AiConfig,
    application_context: Any = None,
    instructions: str = "Answer using only the supplied evidence.",
    mode: Any | None = None,
) -> Any:
    """Embed, retrieve, and generate in one call."""
    chunks = retrieve_chunks(
        query,
        query_embedding=embed_query(query, config=config),
        filters=filters,
        mode=RetrievalMode(mode) if mode is not None else None,
        config=config,
    )
    logger.info(
        "retrieved %s chunk(s) (filters=%s)",
        len(chunks),
        filters,
    )
    return prompt_rag(
        output_model,
        query=query,
        evidence=chunks,
        application_context=application_context,
        instructions=instructions,
        config=config,
    )


class GroundedAnswer(CitedOutput):
    """Cited free-form answer produced from retrieved chunks only."""

    answer: str = Field(min_length=1)

    @field_validator("answer")
    @classmethod
    def nonblank_answer(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("answer must not be blank")
        return value.strip()


def answer_question(
    *,
    query: str,
    filters: dict[str, Any] | None = None,
    config: AiConfig | None = None,
    mode: Any | None = None,
    namespace: str = DEFAULT_NAMESPACE,
    subject_id: int | str | None = None,
    subject_kind: str = DEFAULT_SUBJECT_KIND,
) -> GroundedAnswer:
    """Answer ``query`` from the index using evidence only (no application data)."""
    if not query.strip():
        raise ValueError("query must not be blank")
    active = config or AiConfig()
    scope = dict(filters or {"namespace": namespace})
    if subject_id is not None:
        scope["subject_id"] = f"{subject_kind}:{subject_id}"
    return answer_from_index(
        GroundedAnswer,
        query=query.strip(),
        filters=scope,
        config=active,
        application_context=None,
        instructions=(
            "Answer the question using only the supplied evidence. "
            "Be concise and accurate. Cite every chunk that supports the answer."
        ),
        mode=mode,
    )
