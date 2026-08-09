"""Minimal Azure index setup, chunking, embedding, and sync example."""

import os

from mesozoica_ai.knowledge import (
    KnowledgeSettings,
    create_knowledge_base,
    create_knowledge_index,
)
from mesozoica_ai.sources import WikipediaSource

settings = KnowledgeSettings()
index = create_knowledge_index(settings)
index.ensure()  # Use index.recreate() only when deletion is explicitly intended.

documents = WikipediaSource(user_agent=os.environ["WIKIPEDIA_USER_AGENT"]).fetch(
    "Triceratops"
)
for document in documents:
    document.metadata.update(namespace="example", subject_id="animal:triceratops")

result = create_knowledge_base(settings).sync(
    documents,
    scope={"namespace": "example", "subject_id": "animal:triceratops", "source": "wikipedia"},
)
print(result.model_dump_json(indent=2))
