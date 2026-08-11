# RAG Operations

## Credentials and rotation

Core Azure access uses API keys by product decision. Store all keys as Railway secrets or Key Vault references, never in source control or logs.

- `AZURE_SEARCH_ADMIN_KEY` can create indexes and write/delete documents. Restrict it to indexing jobs.
- `AZURE_SEARCH_QUERY_KEY` is read-only and should be used by retrieval services.
- `AZURE_OPENAI_API_KEY` calls embedding and chat deployments.
- Foundry cloud evaluation separately uses `DefaultAzureCredential` and RBAC.

Rotate one credential at a time: add/activate the replacement, update the secret, restart consumers, verify, then revoke the old key. Key Vault-backed secret references avoid copying values into deployment configuration.

The split mirrors runtime permissions: `KnowledgeConfig` owns Search and embedding
configuration; `RagConfig` owns only chat and prompt-budget settings.

## Cost controls

Changed-only vectors, metadata-only merges, bounded batches, ten OpenAlex works, and fixed retrieval depths limit variable cost. OpenAlex GROBID TEI downloads cost ~$0.01 each (free keys get ~$1/day); failed downloads are skipped with no abstract fallback. The largest cost levers are acquired subjects, OpenAlex full-text downloads, embedding dimensions, snapshot churn, evaluation case/mode count, and generation completion allowance. Structured logs expose counts and durations but never raw content, prompts, query parameters, or secrets.

## Fingerprints and resume behavior

Each dinosaur/source is committed independently as a `dinosaur_knowledge_source` row (with child `dinosaur_knowledge_doc` and `dinosaur_knowledge_chunk` rows). A source is current only when both `indexed_hash == content_hash` and `indexed_pipeline_fingerprint` equals the active pipeline. Changing schema, chunking, tokenizer, embedding deployment, or dimensions therefore makes successful sources eligible for indexing without `--overwrite`. Embeddings live on chunk rows so Azure ingest can retry without re-embedding.

Status shows abbreviated content/pipeline fingerprints and one reason: acquisition missing, content changed, pipeline changed, failed/running/pending, or current. Source acquisition failures and index failures remain visible and retry independently.

## Index lifecycle and recovery

Normal setup creates a missing index or strictly validates fields, dimensions, semantic configuration, typed dates, and fingerprint support. It never edits or recreates an existing index.

`--recreate-index` deletes the configured index, creates it again, and clears every acquisition snapshot's indexing checkpoint. It causes retrieval downtime and must be run unscoped so every successful snapshot is eligible for rebuild. Verify endpoint and `AZURE_SEARCH_INDEX` first.

For the schema-v2 rollout in this revision:

1. Apply the Alembic migration and replace `AZURE_SEARCH_API_KEY` with separate admin/query secrets.
2. Run acquisition once with `--overwrite` for the ten golden genera so snapshots use hierarchical Wikipedia provenance.
3. Run one unscoped `dinosaur_knowledge --recreate-index`; the former schema is intentionally incompatible.
4. Let indexing finish/resume, inspect status until every selected row is current, then run the golden evaluation.

External reads retry transport failures, HTTP 429, and retryable 5xx only. They honor numeric or HTTP-date `Retry-After` within a maximum delay. Normal 4xx failures are immediate. Azure batch writes inspect each document result, retain successful progress, and retry only transient failed keys. Stale deletion occurs after successful writes.

Recovery sequence:

1. Inspect `knowledge_status` (library helper) and logs for the exact stage/source.
2. Correct credentials, schema, provider, or configuration.
3. Rerun `dinosaur_knowledge` for failed/stale sources; use `--overwrite` only to refresh successful source snapshots.
4. Fingerprint changes need no overwrite for indexing eligibility.
5. Recreate only for an explicitly diagnosed incompatible index (`--recreate-index`).
6. Run the golden evaluation (library scripts under `backend/rag/scripts/`) before production rollout.
