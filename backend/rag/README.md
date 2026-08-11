# Mesozoica AI

`mesozoica_ai` is a typed RAG toolkit for Mesozoica: ingest source documents,
embed into Postgres, sync into Azure AI Search, retrieve chunks, and generate
cited structured answers.

## Start here

**[docs/USAGE.md](docs/USAGE.md)** — what each function does, where data is
stored, and copy-paste sequences.

Also:

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — package boundaries
- [docs/EVALUATION.md](docs/EVALUATION.md) — golden metrics and Foundry
- [docs/OPERATIONS.md](docs/OPERATIONS.md) — Azure / Railway recovery

## Layout

```text
mesozoica_ai/
  __init__.py     pipeline verbs only
  common/         AiConfig, Document, checkpoints, store_documents
  sources/        openalex.py, http.py, helpers.py
  index/          chunk / embed / sync / retrieve / embed_knowledge / ingest_knowledge
  generate/       prompt_rag, answer_from_index, generate_quiz
  evaluate/       offline + live metrics, knowledge_status
```

## Quick import

```python
from mesozoica_ai import (
    AiConfig,
    retrieve_openalex,
    ensure_index,
    sync_documents,
    embed_query,
    retrieve_chunks,
    prompt_rag,
)
from mesozoica_ai.common import store_documents
from mesozoica_ai.generate import generate_quiz, answer_from_index
from mesozoica_ai.index import embed_knowledge, ingest_knowledge
from mesozoica_ai.evaluate import evaluate_knowledge, knowledge_status
```

## Scripts

```bash
cd backend
.venv/bin/python rag/scripts/01_acquire_dinosaur_knowledge.py
.venv/bin/python rag/scripts/01_acquire_dinosaur_knowledge.py --dinos Tyrannosaurus
.venv/bin/python rag/scripts/02_embed_dinosaur_knowledge.py
.venv/bin/python rag/scripts/03_ingest_dinosaur_knowledge.py
.venv/bin/python rag/scripts/04_generate_quiz.py --dinos Triceratops
.venv/bin/python rag/scripts/04_generate_quiz.py --dinos Triceratops --chunks-only
.venv/bin/python rag/scripts/05_answer_question.py --question "What horns did Triceratops have?" --dinos Triceratops
.venv/bin/python rag/scripts/06_evaluate_retrieval.py
.venv/bin/python -m pytest rag/tests -q
```

1. **Acquire** — latest `dinosaur_type_revision` Wikipedia article + OpenAlex → Postgres `documents`
2. **Embed** — SQL documents → chunk / embed → Postgres `embedded_chunks`
3. **Ingest** — SQL embeddings → Azure Search
