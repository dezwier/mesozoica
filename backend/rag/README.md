# Mesozoica AI

`mesozoica_ai` is a deliberately small classic RAG toolkit: acquire source documents, synchronize an Azure AI Search index, retrieve controlled evidence, and ask Azure OpenAI for a strict Pydantic result. It is generic; dinosaur selection and checkpointing live in the backend ingestion feature.

LangChain handles Azure OpenAI embeddings/chat, recursive splitting, prompt composition, callbacks, and strict JSON-schema output. The Azure Search SDK remains direct so schema validation, exact filters, partial writes, and destructive index operations stay explicit.

## Package layout

```text
mesozoica_ai/
  sources/         Wikipedia and OpenAlex acquisition
  knowledge/  document processing, Azure indexing, sync, and retrieval
  rag/             prompt assembly, generation, validation, and evaluation
```

Only an empty package marker (`__init__.py`) and `py.typed` live beside these folders.
`py.typed` is the standard PEP 561 marker that tells Python tooling this installed
package includes type information; it must remain at the package root. Models,
settings, errors, and tokenizer helpers live with the subpackage that owns them.

The three subpackages do not import one another. Application code orchestrates the
boundaries explicitly: persist source output, validate it as a knowledge-base
document, retrieve chunks, then map those chunks to `rag.Evidence`. This keeps the
library reusable and makes every remote call visible at the call site.

## Five-minute setup

Install from the repository root:

```bash
make backend-install
```

Configure `backend/.env`:

```dotenv
AZURE_OPENAI_ENDPOINT=https://RESOURCE.openai.azure.com
AZURE_OPENAI_API_KEY=...
AZURE_OPENAI_EMBEDDING_DEPLOYMENT=text-embedding-3-small
AZURE_OPENAI_CHAT_DEPLOYMENT=gpt-4.1-mini
AZURE_OPENAI_EMBEDDING_DIMENSIONS=1536
AZURE_SEARCH_ENDPOINT=https://SERVICE.search.windows.net
AZURE_SEARCH_ADMIN_KEY=...
AZURE_SEARCH_QUERY_KEY=...
AZURE_SEARCH_INDEX=dinosaur-knowledge
WIKIPEDIA_USER_AGENT=MesozoicaBot/1.0 (https://mesozoica.app; contact@example.com)
OPENALEX_API_KEY=...
```

Use an Azure Search admin key only in indexing processes. Give retrieval processes
the query key. `KnowledgeBaseSettings` validates embedding, Search, chunking,
retrieval, and batching configuration. `RagSettings` contains only Azure OpenAI chat
and prompt-budget configuration.

This revision uses an intentionally incompatible schema v2. Existing v1 indexes require the explicit unscoped rollout documented in [Operations](docs/OPERATIONS.md); normal setup will fail rather than mutate them.

## Public API

Import from the subpackage that performs the work. The package root deliberately
re-exports nothing.

```python
from mesozoica_ai.sources import WikipediaSource
from mesozoica_ai.knowledge import KnowledgeBaseSettings, RetrievalRequest
from mesozoica_ai.rag import Evidence, RagSettings
```

- `sources.WikipediaSource.fetch(title)` returns hierarchical section documents pinned to a revision.
- `sources.OpenAlexSource.search(query, limit=10)` returns non-retracted article/preprint abstracts.
- `KnowledgeBase.sync(documents, scope)` embeds new/vector-changed chunks, merges metadata-only changes, then deletes stale chunks.
- `KnowledgeBase.retrieve(request)` returns a `RetrievalResult` with selected chunks, timing, raw counts, rejection counts, mode, and pipeline fingerprint.
- `Rag.generate(..., evidence=...)` returns `RagResult[T]` with strict output, exact prompt diagnostics, evidence JSONL, and usage.
- `rag.evaluation.evaluate_retrieval(...)` computes deterministic precision/recall/hit-rate/MRR/nDCG through an application-owned retrieval callback.

The default is semantic-hybrid retrieval: 50 vector candidates, 24 ranked candidates fetched, exact-content deduplication, at most two chunks per source document, and eight selected chunks. Other modes never silently fall back. Citation validation is opt-in and explicit: generated schemas that require citations inherit `CitedOutput`.

## Four examples

Every example has `main()` and is safe to import:

```bash
cd backend
.venv/bin/python rag/scripts/01_retrieve_documents.py Triceratops
.venv/bin/python rag/scripts/02_build_knowledge_base.py Triceratops
.venv/bin/python rag/scripts/03_generate_quiz.py Triceratops
.venv/bin/python rag/scripts/04_evaluate_retrieval.py path/to/cases.jsonl
```

The first only reads public sources. The second may create a missing Search index and
writes one exact scope. The third shows the orchestration explicitly: retrieve, map
chunks to evidence, generate. The fourth evaluates through a similarly explicit
retrieval adapter. Index recreation exists only as an application command.

## More detail

- [Architecture](docs/ARCHITECTURE.md)
- [Operations](docs/OPERATIONS.md)
- [Evaluation](docs/EVALUATION.md)

Tests are offline:

```bash
cd backend
.venv/bin/python -m pytest rag/tests -q
```
