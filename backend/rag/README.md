# Mesozoica AI

`mesozoica_ai` is a typed RAG toolkit for Mesozoica: fetch sources, sync into
Azure AI Search, retrieve chunks, and generate cited structured answers.

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
  sources/        wikipedia.py, openalex.py, http.py, helpers.py
  index/          chunk / embed / sync / retrieve / index_knowledge
  generate/       prompt_rag, answer_from_index, generate_quiz
  evaluate/       offline + live metrics, knowledge_status
```

## Quick import

```python
from mesozoica_ai import (
    AiConfig,
    retrieve_wikipedia,
    retrieve_openalex,
    ensure_index,
    sync_documents,
    embed_query,
    retrieve_chunks,
    prompt_rag,
)
from mesozoica_ai.common import store_documents
from mesozoica_ai.generate import generate_quiz, answer_from_index
from mesozoica_ai.index import index_knowledge
from mesozoica_ai.evaluate import evaluate_knowledge, knowledge_status
```

## Scripts

```bash
cd backend
.venv/bin/python rag/scripts/01_acquire_dinosaur_knowledge.py
.venv/bin/python rag/scripts/01_acquire_dinosaur_knowledge.py --dinos Tyrannosaurus
.venv/bin/python rag/scripts/02_index_dinosaur_knowledge.py
.venv/bin/python rag/scripts/03_generate_quiz.py
.venv/bin/python rag/scripts/04_evaluate_retrieval.py
.venv/bin/python -m pytest rag/tests -q
```

1. **Acquire** — Wikipedia + OpenAlex → Postgres `dinosaur_knowledge`
2. **Index** — SQL snapshots → chunk / embed / Azure Search
