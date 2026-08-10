# RAG Architecture

## Module boundaries

The source tree has three explicit responsibilities:

- `sources` acquires normalized documents and knows nothing about Azure Search;
- `knowledge` validates documents, chunks, embeds, synchronizes, inspects, and
  queries Azure Search;
- `rag` composes caller-supplied evidence with application context, generates a
  validated result, and contains optional evaluation tooling.

The package root re-exports nothing. Each subpackage owns its models, settings,
errors, and tokenizer use. The only other root file is the mandatory `py.typed`
distribution marker. Evaluation is nested under `rag.evaluation`; its Foundry SDK
remains an optional dependency and is not imported by the online `rag` API.

No subpackage imports another. The ingestion application is the composition root:

```text
sources.SourceDocument
  -> persisted snapshot
  -> knowledge.KnowledgeDocument
  -> KnowledgeBase.retrieve(...).chunks
  -> rag.Evidence
  -> Rag.generate(...)
```

The explicit conversion steps are small and intentional. They prevent source
providers from knowing about Azure Search and prevent generation from hiding a
retrieval call.

## Controlled two-step flow

```text
Wikipedia / OpenAlex -> SourceDocument -> snapshot -> KnowledgeDocument -> chunks
                                                                      -> embeddings
                                                              -> Azure AI Search
application query -> query embedding -> semantic-hybrid ranking -> evidence policy
selected chunks -> Evidence -> app data + exact prompt budget -> Pydantic output
golden judgments -> local retrieval metrics / optional Foundry generation judges
```

This is intentionally classic RAG. There is no agentic retrieval, query rewriting, or second learned reranker. Azure hybrid ranking combines lexical and vector signals; Azure semantic ranking reorders the fetched candidates. Quality is established by the pinned golden dataset, not by adding opaque stages.

## Documents, chunks, and hashes

Sources return `SourceDocument` values with typed `SourceMetadata`. The application
stores their JSON snapshots and validates them as knowledge-base documents before
indexing. Wikipedia headings retain depth, path, ordinal, revision, anchor,
canonical URL, and license. OpenAlex returns abstract and bibliographic provenance.

Chunking never crosses a source document/section boundary. `tiktoken` measures the configured embedding encoding at a 500-token target with 75-token overlap. Title and hierarchical section path are present only in `embedding_text`, not stored evidence.

Three identities serve different purposes:

- `embedding_hash` changes when vector input or embedding compatibility changes;
- `document_hash` changes when any stored text or metadata changes;
- `pipeline_fingerprint` changes with index schema, chunker settings/version, embedding tokenizer, deployment, dimensions, or chunk size/overlap.

Stable chunk IDs exclude mutable metadata. This permits vector-preserving metadata merges. Synchronization writes all new/vector-changed chunks, merges metadata-only changes, and only then deletes stale chunks, so a partial write cannot erase the last usable scope.

## Retrieval and prompt trust boundary

Azure returns 24 candidates by default. `EvidencePolicy` applies an optional evaluated semantic-score threshold, exact-content deduplication, and a per-document cap before selecting eight. Empty/insufficient evidence raises a typed error.

The application converts selected chunks to the tiny `Evidence` contract and passes
them to `Rag.generate`. Application context and evidence are JSON-delimited as
untrusted data. The exact prompt budget reserves system text, instructions, query,
application JSON, output JSON schema, completion allowance, and safety margin before
adding evidence. Provider-native strict JSON schema validates output; only
`CitedOutput` subclasses trigger citation validation.

## Dependency choices

LangChain removes provider boilerplate where its abstraction is useful: Azure OpenAI v1 clients, embeddings, splitting, prompts, structured output, callbacks/tracing. Azure Search remains direct because its index schema, semantic configuration, vector candidate count, OData filters, per-document write results, and recreate semantics are production contracts rather than interchangeable implementation details.
