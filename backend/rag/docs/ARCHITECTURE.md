# RAG Architecture

## Package root is a façade

`mesozoica_ai/__init__.py` re-exports pipeline callables only. Domain packages own
the rest:

| Package | Role | May import |
|---|---|---|
| `common` | config, models, tokens, checkpoint/`store_documents` | nothing else in mesozoica_ai |
| `sources` | `retrieve_openalex` (+ http/helpers) | `common` |
| `index` | chunk/embed/sync/retrieve + batch index | `common` |
| `generate` | prompt_rag, answer_from_index, answer_question, quiz | `common`, `index` |
| `evaluate` | offline/live metrics, status | `common`, `index` |

```text
dinosaur_type_revision (Wikipedia) / retrieve_openalex
  -> store_documents (Postgres documents; acquire script)
  -> prepare_embeddings / embed_knowledge (Postgres embedded_chunks)
  -> sync_embedded_chunks / ingest_knowledge (Azure Search)

embed_query
  -> retrieve_chunks
  -> prompt_rag / generate_quiz
  -> Pydantic output
```

## Controlled classic RAG

Section-bounded chunking, incremental sync fingerprints, evidence policy, and
prompt budgets remain inside `index` / `generate`. No agentic loops.

## Usage

Function-by-function guide and end-to-end sequences: [USAGE.md](USAGE.md).
