# Mesozoica AI usage

How to use `mesozoica_ai`: what each function does, where data lives, and
copy-paste sequences for the common paths.

## Mental model

Three durable stages, one retrieval path:

| Stage | Lives in |
|---|---|
| Wikipedia text (from `dinosaur_type_revision`) / OpenAlex | Memory only (`Document` objects) |
| Job tracking (acquire/embed/index) | PostgreSQL `dinosaur_knowledge_source` |
| Durable raw sections | PostgreSQL `dinosaur_knowledge_doc` |
| Chunked embeddings | PostgreSQL `dinosaur_knowledge_chunk` |
| Searchable vectors | Azure AI Search |
| Model answers | Memory only (your Pydantic type) |

```text
dinosaur_type_revision / retrieve_openalex
        │
        ▼
   store_documents → Postgres dinosaur_knowledge_source + dinosaur_knowledge_doc
        │
        ▼
   prepare_embeddings → Postgres dinosaur_knowledge_chunk
        │
        ▼
ensure_index  →  sync_embedded_chunks   (or ad-hoc sync_documents)
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

### `retrieve_openalex(query, *, api_key, user_agent, limit=10, exclude_work_ids=None, metadata=None)`

Fetches up to ``limit`` *new* OpenAlex works (relevance-ranked) with GROBID TEI
full text and returns section `list[Document]` **in memory**. Pass
``exclude_work_ids`` to skip papers already stored and top up toward a
per-dinosaur target (see ``01_acquire_dinosaur_knowledge.py``). Titles are
logged as papers are acquired.

Search is limited to `has_content.grobid_xml:true`. Failed or empty TEI
downloads are skipped — there is no abstract fallback. Each TEI download costs
OpenAlex content credits (~$0.01).

```python
from mesozoica_ai import retrieve_openalex

papers = retrieve_openalex(
    "Triceratops",
    user_agent=os.environ["WIKIPEDIA_USER_AGENT"],
    api_key=os.environ["OPENALEX_API_KEY"],
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

### `prepare_embeddings(documents, *, config, existing=None)`

Chunks documents and embeds only chunks whose vector identity changed.
Pass prior SQL chunk rows as ``existing`` to reuse vectors after a
failed Azure ingest (or any re-run with unchanged content).

### `index_chunks(embedded_chunks, *, config)`

Upserts embedded chunks into Azure Search. Does **not** remove stale chunks for
a scope; prefer `sync_embedded_chunks` / `sync_documents` for production ingest.

### `sync_embedded_chunks(embedded_chunks, *, scope, config)`

**Preferred Azure ingest when vectors are already in SQL.** Upserts, merges
metadata-only changes, deletes stale scope chunks, and verifies keys — with
**no** embedding API calls.

### `sync_documents(documents, *, scope, config)`

Ad-hoc convenience: `prepare_embeddings` then `sync_embedded_chunks` (no SQL
cache). Prefer the embed/ingest scripts for production dinosaur knowledge.

```python
from mesozoica_ai import AiConfig, ensure_index, retrieve_openalex, sync_documents

config = AiConfig()
docs = retrieve_openalex(
    "Triceratops",
    user_agent=os.environ["WIKIPEDIA_USER_AGENT"],
    api_key=os.environ["OPENALEX_API_KEY"],
    metadata={"namespace": "mesozoica", "subject_id": "dinosaur:1"},
)

ensure_index(config=config)
result = sync_documents(
    docs,
    scope={
        "namespace": "mesozoica",
        "subject_id": "dinosaur:1",
        "source": "openalex",
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
- `mode`: keyword, vector, hybrid, or semantic_hybrid. Default comes from
  `RAG_RETRIEVAL_MODE` (package default: `hybrid`). Use `semantic_hybrid` only when
  Azure Search Semantic Ranker is enabled on the service.

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
    filters={"namespace": "mesozoica", "subject_id": "animal:triceratops"},
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

### `answer_question(*, query, filters=..., config=...)`

Cited free-form answer from the index with **no application context**.
Optional `subject_id` adds a dinosaur scope filter.

```python
from mesozoica_ai.generate import answer_question

result = answer_question(query="What did Abrosaurus eat?", subject_id=12)
print(result.answer, result.source_chunk_ids)
```

CLI:

```bash
.venv/bin/python rag/scripts/05_answer_question.py \
  --question "What did Abrosaurus eat?" --dinos Abrosaurus --show-chunks
```

### `generate_quiz(*, subject=..., config=...)`

Builds one cited four-option quiz about a subject from the live index.
Accepts either `subject` (duck-typed `.id` / `.name`) or explicit
`subject_id` / `subject_name`.

```python
from mesozoica_ai.generate import generate_quiz

quiz = generate_quiz(subject_id=7, subject_name="Triceratops")
print(quiz.model_dump_json(indent=2))
```

CLI (exactly one `--dinos`):

```bash
.venv/bin/python rag/scripts/04_generate_quiz.py --dinos Triceratops --difficulty medium
.venv/bin/python rag/scripts/04_generate_quiz.py --dinos Triceratops --chunks-only
.venv/bin/python rag/scripts/04_generate_quiz.py --dinos Triceratops --show-chunks
```

`--chunks-only` prints the retrieval query/filters and each chunk with ranking
scores plus provenance (`source`, `source_id`, `title`, `section`, `source_url`, …).
`--show-chunks` includes that same `chunks` array next to the generated quiz.

---

## Sources (`mesozoica_ai.sources`)

OpenAlex remains a live external source. Wikipedia for dinosaur knowledge is
loaded from `dinosaur_type_revision` by the acquire script (not by this package).

| Function | Role |
|---|---|
| `retrieve_openalex` | Fetch OpenAlex GROBID TEI sections → `list[Document]` |

Helpers live beside them (`http.py`, `helpers.py`). Checkpoint helpers live in
`mesozoica_ai.common` (`store_documents`, `acquire_knowledge`). The multi-subject
SQL wiring is `app.features.ingestion.jobs.dinosaur_knowledge`; the rag script is
only a CLI over that job.

```python
from app.features.ingestion import dinosaur_knowledge_repo
from mesozoica_ai.common import store_documents
from mesozoica_ai.sources import retrieve_openalex

docs = retrieve_openalex(query, api_key=..., user_agent=..., metadata=...)
repo = dinosaur_knowledge_repo(session)
store_documents(repo, subject=subject, source="openalex", documents=docs)
```

---

## Batch index (`mesozoica_ai.index`)

### `embed_knowledge(*, repo, names=None, sources=None, ...)`

For each acquired `dinosaur_knowledge_source` eligible for embedding:

1. `prepare_embeddings` (reuse prior `dinosaur_knowledge_chunk` vectors when hashes match)
2. `replace_chunks` + embed checkpoint fields on the source

### `ingest_knowledge(*, repo, names=None, sources=None, ...)`

For each successfully embedded source eligible for Azure ingest:

1. optionally recreate the Azure index (`recreate_index=True`, full scope only)
2. `ensure_index` unless just recreated
3. `sync_embedded_chunks` from SQL chunks (no embedding API)
4. record pipeline fingerprint on the source index checkpoint

### `index_knowledge(*, repo, names=None, sources=None, ...)`

Compat convenience: `embed_knowledge` then `ingest_knowledge`.

```python
from app.features.ingestion import dinosaur_knowledge_repo
from mesozoica_ai.index import embed_knowledge, ingest_knowledge

with Session(engine) as session:
    repo = dinosaur_knowledge_repo(session)
    embed_knowledge(repo=repo, names=["Triceratops"])
    ingest_knowledge(repo=repo, names=["Triceratops"])
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

### `evaluate_knowledge(*, repo, dataset_path, ...)`

`prepare_retrieval_cases` + `evaluate_against_index` for table-backed snapshots.

### `knowledge_status(repo, *, names=None, ...)`

Prints a human-readable acquire/index status table for checkpoint rows.

### `evaluation_exit(report, comparison=None)`

Prints JSON and returns `0` / `1` for CLI jobs.

---

## End-to-end sequences

### A. Ad-hoc script (no Postgres)

```python
config = AiConfig()
docs = retrieve_openalex(query, api_key=..., user_agent=..., metadata=...)
ensure_index(config=config)
sync_documents(docs, scope=..., config=config)
chunks = retrieve_chunks(q, query_embedding=embed_query(q, config=config), filters=..., config=config)
answer = prompt_rag(MyModel, query=q, evidence=chunks, config=config)
```

### B. Production dinosaur knowledge

```text
dinosaur_type_revision / retrieve_openalex + store_documents  → source + doc tables
embed_knowledge                                               → chunk table (vectors in SQL)
ingest_knowledge                                              → Azure Search
```

Run via the scripts (all genera by default) or the app cron `dinosaur_knowledge`
(same `run_knowledge_job`):

```bash
.venv/bin/python rag/scripts/01_acquire_dinosaur_knowledge.py
.venv/bin/python rag/scripts/01_acquire_dinosaur_knowledge.py --dinos Tyrannosaurus --sources wikipedia
.venv/bin/python rag/scripts/02_embed_dinosaur_knowledge.py --dinos Tyrannosaurus
.venv/bin/python rag/scripts/03_ingest_dinosaur_knowledge.py --dinos Tyrannosaurus
python -m app.crons.runner --job dinosaur_knowledge --dinos Tyrannosaurus
```

### C. Example scripts in this repo

```bash
cd backend
.venv/bin/python rag/scripts/01_acquire_dinosaur_knowledge.py --dinos Triceratops
.venv/bin/python rag/scripts/02_embed_dinosaur_knowledge.py --dinos Triceratops
.venv/bin/python rag/scripts/03_ingest_dinosaur_knowledge.py --dinos Triceratops
.venv/bin/python rag/scripts/04_generate_quiz.py --dinos Triceratops
.venv/bin/python rag/scripts/05_answer_question.py --question "What horns did Triceratops have?" --dinos Triceratops
.venv/bin/python rag/scripts/06_evaluate_retrieval.py
```

---

## Related docs

- [ARCHITECTURE.md](ARCHITECTURE.md) — package boundaries
- [EVALUATION.md](EVALUATION.md) — golden labels and Foundry judges
- [OPERATIONS.md](OPERATIONS.md) — Azure / Railway recovery
