# Mesozoica AI usage

How to use `mesozoica_ai`: what each function does, where data lives, and
copy-paste sequences for the common paths.

## Mental model

Two stores, one pipeline:

| Stage | Lives in |
|---|---|
| Fresh Wikipedia / OpenAlex text | Memory only (`Document` objects) |
| Durable raw sources (optional) | PostgreSQL `rag_source_snapshot` |
| Searchable chunks + vectors | Azure AI Search |
| Model answers | Memory only (your Pydantic type) |

```text
retrieve_wikipedia / retrieve_openalex
        │
        ▼
   (optional) Postgres snapshot via acquire_knowledge
        │
        ▼
ensure_index  →  sync_documents   (or chunk → embed → index_chunks)
        │
        ▼
embed_query  →  retrieve_chunks  →  prompt_rag / generate_quiz
```

Config comes from the environment via `AiConfig()` (Azure OpenAI, Azure Search,
chunk sizes, etc.).

---

## Root pipeline verbs

Import these from `mesozoica_ai`.

### `AiConfig`

Loads Azure / chunking / prompt settings from the process environment.
Pass the same instance through a run so embeddings and search stay consistent.

### `retrieve_wikipedia(title, *, user_agent, metadata=None)`

Fetches Wikipedia sections and returns fingerprinted documents **in memory**.
Does **not** write Postgres or Azure.

```python
from mesozoica_ai import retrieve_wikipedia

wiki = retrieve_wikipedia(
    "Triceratops",
    user_agent=os.environ["WIKIPEDIA_USER_AGENT"],
)
for doc in wiki.documents:
    print(doc.id, doc.metadata.title, len(doc.text))
```

### `retrieve_openalex(query, *, api_key, user_agent, limit=10, metadata=None)`

Fetches OpenAlex works and returns fingerprinted documents **in memory**.

```python
from mesozoica_ai import retrieve_openalex

papers = retrieve_openalex(
    "Triceratops",
    api_key=os.environ["OPENALEX_API_KEY"],
    user_agent=os.environ["WIKIPEDIA_USER_AGENT"],
)
```

### `ensure_index(*, config)`

Creates the Azure AI Search index if missing, or checks that an existing index
matches the expected schema. Call once before writing or searching.

Does **not** delete an existing index. Use `recreate_index` only when you
intentionally wipe the Azure index.

### `chunk_documents(documents, *, config)`

Splits documents into section-aware chunks (still in memory).

### `embed_chunks(chunks, *, config)`

Embeds chunk text with the configured Azure embedding deployment.

### `index_chunks(embedded_chunks, *, config)`

Upserts embedded chunks into Azure Search. Does **not** remove stale chunks for
a scope; prefer `sync_documents` for production ingest.

### `sync_documents(documents, *, scope, config)`

**Preferred ingest.** For one filter `scope` (e.g. namespace + subject + source):

1. chunks documents
2. embeds only chunks whose vector content changed
3. upserts into Azure
4. deletes Azure chunks that disappeared from this scope

```python
from mesozoica_ai import AiConfig, ensure_index, retrieve_wikipedia, sync_documents

config = AiConfig()
docs = retrieve_wikipedia(
    "Triceratops",
    user_agent=os.environ["WIKIPEDIA_USER_AGENT"],
    metadata={"namespace": "example", "subject_id": "animal:triceratops"},
).documents

ensure_index(config=config)
result = sync_documents(
    docs,
    scope={
        "namespace": "example",
        "subject_id": "animal:triceratops",
        "source": "wikipedia",
    },
    config=config,
)
print(result.model_dump_json(indent=2))
```

### `embed_query(query, *, config)`

Embeds a search query for vector / hybrid retrieval.

### `retrieve_chunks(query, *, query_embedding, filters, config, ...)`

Searches Azure AI Search and returns grounded chunks (with optional diagnostics).

- `filters`: usually `namespace` / `subject_id` / `source`
- `mode`: keyword, vector, hybrid, or semantic_hybrid (default)

### `prompt_rag(output_model, *, query, evidence, config, ...)`

Calls the chat model with only the supplied evidence and returns a validated
Pydantic object. Subclass `CitedOutput` when answers must cite chunk IDs.

```python
from mesozoica_ai import AiConfig, embed_query, prompt_rag, retrieve_chunks
from mesozoica_ai.common import CitedOutput

class Answer(CitedOutput):
    text: str

config = AiConfig()
query = "What horns did Triceratops have?"
chunks = retrieve_chunks(
    query,
    query_embedding=embed_query(query, config=config),
    filters={"namespace": "example", "subject_id": "animal:triceratops"},
    config=config,
)
answer = prompt_rag(
    Answer,
    query=query,
    evidence=chunks,
    instructions="Answer briefly using only the evidence.",
    config=config,
)
```

---

## Generation helpers (`mesozoica_ai.generate`)

### `answer_from_index(output_model, *, query, filters, config, ...)`

One-shot: `embed_query` → `retrieve_chunks` → `prompt_rag`.

### `generate_quiz(*, subject=..., config=...)`

Builds one cited four-option quiz about a subject from the live index.
Accepts either `subject` (duck-typed `.id` / `.name`) or explicit
`subject_id` / `subject_name`.

```python
from mesozoica_ai.generate import generate_quiz

quiz = generate_quiz(subject_id=7, subject_name="Triceratops")
print(quiz.model_dump_json(indent=2))
```

---

## Sources + durable acquire (`mesozoica_ai.sources`)

Use these when many subjects must be fetched with resume/retry into Postgres.

### `bound_wikipedia` / `bound_openalex`

Return per-source retrieve callables with credentials already bound.

### `require_openalex_credentials(sources, *, api_key, dry_run=False)`

Fails fast if OpenAlex is requested without an API key.

### `SqlSnapshotStore(session, *, model=RagSourceSnapshot)`

SQLModel adapter for the checkpoint table. The app owns the table class
(`RagSourceSnapshot`); the library owns the store behavior.

### `acquire_knowledge(*, subjects, retrievers, store, ...)`

For each subject × source:

1. load or create a Postgres checkpoint row
2. skip if already succeeded (unless `overwrite`)
3. call that source’s retriever
4. save documents + content/source hashes on the row
5. mark indexing pending when content changed

Writes **Postgres only**, not Azure.

`retrievers` maps source name → callable `(query, *, metadata=...) -> RetrievedDocuments`.

```python
from mesozoica_ai.sources import (
    SqlSnapshotStore,
    acquire_knowledge,
    bound_openalex,
    bound_wikipedia,
)

with Session(engine) as session:
    summary = acquire_knowledge(
        subjects=subjects,
        retrievers={
            "wikipedia": bound_wikipedia(user_agent=settings.wikipedia_user_agent),
            "openalex": bound_openalex(
                api_key=settings.openalex_api_key,
                user_agent=settings.wikipedia_user_agent,
            ),
        },
        store=SqlSnapshotStore(session, model=RagSourceSnapshot),
        sources=["wikipedia", "openalex"],
    ).print_exit()
```

---

## Batch index (`mesozoica_ai.index`)

### `index_knowledge(*, store, names=None, sources=None, ...)`

For each acquired Postgres snapshot eligible for indexing:

1. optionally recreate the Azure index (`recreate_index=True`, full scope only)
2. `ensure_index` unless just recreated
3. `sync_documents` for that snapshot’s scope
4. record pipeline fingerprint on the checkpoint

```python
from mesozoica_ai.index import index_knowledge
from mesozoica_ai.sources import SqlSnapshotStore

with Session(engine) as session:
    index_knowledge(
        store=SqlSnapshotStore(session, model=RagSourceSnapshot),
        names=["Triceratops"],
    ).print_exit()
```

### `recreate_index(*, config)` / `pipeline_fingerprint(*, config)`

Explicit Azure wipe-and-rebuild, and the compatibility hash used to detect when
unchanged content must be re-indexed after pipeline changes.

---

## Evaluate (`mesozoica_ai.evaluate`)

### `load_retrieval_cases(path)` / `prepare_retrieval_cases(cases, snapshots)`

Load golden JSONL cases, then bind them to current snapshot hashes and subject
filters. Raises if labels are missing or stale.

### `evaluate_against_index(cases, *, config, mode=...)`

Runs local precision / recall / hit-rate / MRR / nDCG against the live Azure
index. Optionally writes a report and compares a baseline.

### `evaluate_knowledge(*, store, dataset_path, ...)`

`prepare_retrieval_cases` + `evaluate_against_index` for store-backed snapshots.

### `knowledge_status(store, *, names=None, ...)`

Prints a human-readable acquire/index status table for checkpoint rows.

### `evaluation_exit(report, comparison=None)`

Prints JSON and returns `0` / `1` for CLI jobs.

---

## End-to-end sequences

### A. Ad-hoc script (no Postgres)

```python
config = AiConfig()
docs = retrieve_wikipedia(title, user_agent=..., metadata=...).documents
ensure_index(config=config)
sync_documents(docs, scope=..., config=config)
chunks = retrieve_chunks(q, query_embedding=embed_query(q, config=config), filters=..., config=config)
answer = prompt_rag(MyModel, query=q, evidence=chunks, config=config)
```

### B. Production dinosaur knowledge (app runner)

```text
acquire_knowledge   → Postgres snapshots
index_knowledge     → Azure Search
generate_quiz       → one cited quiz (optional)
evaluate_knowledge  → golden metrics (optional)
knowledge_status    → ops table
```

### C. Example scripts in this repo

```bash
cd backend
.venv/bin/python rag/scripts/01_retrieve_documents.py Triceratops
.venv/bin/python rag/scripts/02_build_knowledge_base.py Triceratops --sync
.venv/bin/python rag/scripts/03_generate_quiz.py Triceratops
```

---

## Related docs

- [ARCHITECTURE.md](ARCHITECTURE.md) — package boundaries
- [EVALUATION.md](EVALUATION.md) — golden labels and Foundry judges
- [OPERATIONS.md](OPERATIONS.md) — Azure / Railway recovery
