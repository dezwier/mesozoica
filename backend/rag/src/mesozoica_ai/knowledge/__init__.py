"""Document processing, Azure indexing, synchronization, and retrieval."""

from .service import KnowledgeBase
from .factory import (
    create_knowledge_base,
    create_knowledge_index,
    create_knowledge_inspector,
)
from .index import AzureKnowledgeIndex
from .inspection import KnowledgeInspector
from .models import (
    EvidencePolicy,
    KnowledgeDocument,
    RetrievalMode,
    RetrievalRequest,
    RetrievalResult,
    RetrievedChunk,
)
from .settings import KnowledgeBaseSettings

__all__ = [
    "AzureKnowledgeIndex",
    "KnowledgeBase",
    "KnowledgeBaseSettings",
    "KnowledgeDocument",
    "KnowledgeInspector",
    "EvidencePolicy",
    "RetrievalMode",
    "RetrievalRequest",
    "RetrievalResult",
    "RetrievedChunk",
    "create_knowledge_base",
    "create_knowledge_index",
    "create_knowledge_inspector",
]
