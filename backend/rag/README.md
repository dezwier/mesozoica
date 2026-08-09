# Mesozoica AI

`mesozoica_ai` is a small, source-agnostic retrieval-augmented generation toolkit. It uses LangChain for Azure OpenAI embeddings, token-aware recursive splitting, prompt composition, and native JSON-schema structured output. It uses the Azure AI Search SDK directly for predictable index lifecycle, synchronization, filters, and hybrid/semantic retrieval.

The package contains no dinosaur business rules. Mesozoica's resumable dinosaur orchestration lives in `app.features.ingestion.application.knowledge`; its cron modules are thin entrypoints.

## Install and configure

`make backend-install` installs the package editable with its test extras. The backend Docker image installs the core package.

Required for Azure indexing/querying:

```dotenv
AZURE_OPENAI_ENDPOINT=https://RESOURCE.openai.azure.com
AZURE_OPENAI_API_KEY=...
AZURE_OPENAI_EMBEDDING_DEPLOYMENT=text-embedding-3-small
AZURE_OPENAI_CHAT_DEPLOYMENT=gpt-4.1-mini
AZURE_OPENAI_EMBEDDING_DIMENSIONS=1536
AZURE_SEARCH_ENDPOINT=https://SERVICE.search.windows.net
AZURE_SEARCH_API_KEY=...
AZURE_SEARCH_INDEX=dinosaur-knowledge
```

The Azure OpenAI endpoint may also include `/openai/v1`. Optional controls are `RAG_CHUNK_SIZE` (default 500), `RAG_CHUNK_OVERLAP` (75), `RAG_CONTEXT_TOKEN_BUDGET` (6000), and `RAG_SEMANTIC_CONFIGURATION`. Source retrieval also uses `WIKIPEDIA_USER_AGENT`, `OPENALEX_API_KEY`, and `OPENALEX_MAX_WORKS`.

## Core interfaces

- `WikipediaSource.fetch(title)` returns one validated document per useful article section, including revision, URL, and provenance.
- `OpenAlexSource.search(query, limit=10)` returns abstract-bearing, non-retracted articles/preprints with bibliographic metadata.
- `KnowledgeBase.sync(documents, scope)` embeds only changed chunks, upserts in batches, and removes stale chunks in that exact scope.
- `KnowledgeBase.retrieve(request)` supports keyword, vector, hybrid, and semantic-hybrid modes with exact-match promoted metadata filters.
- `StructuredRag.generate(...)` packs application context and untrusted evidence into a bounded prompt and returns a generic `RagResult[T]` validated against the requested Pydantic model.

Chunk IDs and hashes are stable across runs and include section text, relevant metadata, splitter version, embedding deployment, and vector dimensions. Titles and section labels are prefixed only to embedding input; stored evidence remains clean and citable.

Semantic-hybrid is the default retrieval mode with 50 vector candidates and 8 returned chunks. Modes fail explicitly if the configured service cannot execute them; no silent fallback occurs. Filter keys are allowlisted and values are OData-escaped.

## Index lifecycle

Normal `ensure()` calls never delete an index. A schema or vector-dimension mismatch fails with an actionable error. `recreate()` deletes and rebuilds the configured index and must only be called deliberately. In the application workflow, `--recreate-index` also marks every successfully acquired snapshot pending for reindexing.

## Evaluation

`evaluate_retrieval` reads validated relevance cases directly or from JSONL and deterministically reports precision@k, recall@k, hit-rate@k, MRR, and nDCG. `FoundryRagEvaluator` is an optional adapter for Microsoft Foundry document-retrieval, groundedness, relevance, and response-completeness evaluation. Install `mesozoica-ai[foundry]`; pass `AZURE_AI_PROJECT_ENDPOINT` and an `AZURE_AI_JUDGE_MODEL` from the calling application. Authentication uses `DefaultAzureCredential`, while core Azure OpenAI/Search calls use API keys.

CI tests mock Azure and network clients. Run:

```bash
cd backend
.venv/bin/python -m pytest rag/tests -q
```

## Minimal examples

The scripts are intentionally short and contain no application orchestration:

```bash
cd backend
.venv/bin/python rag/scripts/01_retrieve_documents.py
.venv/bin/python rag/scripts/02_build_knowledge_base.py
.venv/bin/python rag/scripts/03_generate_quiz.py
```

The first performs external reads. The second writes to Azure AI Search. The third queries Azure AI Search and calls Azure OpenAI.
