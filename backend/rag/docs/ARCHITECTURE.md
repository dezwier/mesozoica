# RAG Architecture

## Package root is a façade

`mesozoica_ai/__init__.py` re-exports pipeline callables only. Domain packages own
the rest:

| Package | Role | May import |
|---|---|---|
| `common` | config, models, tokens, checkpoint/resume | nothing else in mesozoica_ai |
| `sources` | retrieve + acquire into Postgres snapshots | `common` |
| `index` | chunk/embed/sync/retrieve + batch index | `common` |
| `generate` | prompt_rag, answer_from_index, quiz | `common`, `index` |
| `evaluate` | offline/live metrics, status | `common`, `index` |

```text
retrieve_wikipedia / retrieve_openalex
  -> Postgres snapshot (acquire_knowledge)
  -> sync_documents / index_knowledge
  -> Azure AI Search

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
