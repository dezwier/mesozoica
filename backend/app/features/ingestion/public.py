"""Supported cross-feature ingestion surface."""

from app.features.ingestion.domain.dinosaur_names import dino_name_match_clause, parse_dino_names
from app.features.ingestion.application.dinosaur_knowledge.repository import (
    dinosaur_knowledge_repo,
)
from app.features.ingestion.application.fossil_enrichment.validate import (
    BODY_SUBCATEGORIES,
    TRACE_SUBCATEGORIES,
    UNKNOWN,
)
from app.features.ingestion.infrastructure.wikipedia.parser import prepare_article_for_display
from app.features.ingestion.models import (
    DinosaurKnowledge,
    DinosaurKnowledgeChunk,
    DinosaurKnowledgeDoc,
    DinosaurKnowledgeSource,
)
from app.features.media.public import fossil_to_enrichment_prompt_dict

__all__ = [name for name in globals() if not name.startswith("_")]
