# RAG Evaluation

## Golden labels and staleness

The application dataset contains 30 cases: Wikipedia factual, scholarly/OpenAlex, and cross-source judgments for each of ten genera. Relevance is graded per stable source document ID. Each case pins the source snapshot hash used while reviewing it.

Run acquisition for all ten subjects before evaluation. After adopting the hierarchical source parser in this revision, use `--overwrite` once even for previously successful snapshots. If any current source hash differs, the application job refuses to calculate metrics. Review the changed source, update judgments if needed, and deliberately replace the stored hash; never bypass staleness or compare metrics from different evidence.

## Local retrieval metrics

```bash
make run-dinosaur-knowledge-evaluate CRON_EXTRA='--retrieval-mode semantic_hybrid --output-report /tmp/rag-report.json'
```

Sweep one variable at a time using `keyword`, `vector`, `hybrid`, and `semantic_hybrid`, recording candidate/fetch/top-k and the pipeline fingerprint. Precision measures irrelevant material admitted; recall measures labeled material found; hit-rate catches total misses; MRR rewards an early first relevant document; nDCG rewards correct graded ordering.

Compare a release candidate to a baseline:

```bash
make run-dinosaur-knowledge-evaluate CRON_EXTRA='--baseline-report baseline.json --maximum-regression 0.02'
```

The default allows at most two absolute percentage points of regression in every aggregate metric. Tune a semantic reranker threshold only from these experiments and record it with the resulting fingerprint; the default remains disabled.

## Foundry judges

Install `mesozoica-ai[foundry]` and configure an Azure AI Project plus a judge deployment. `FoundryRagEvaluator` uses current typed evaluation criteria for document retrieval, retrieval relevance, groundedness, response relevance, and optional response completeness. It uses `deployment_name`, bounds polling, reports terminal/timeout state, retrieves output items, and returns evaluation ID, run ID, and report URL.

Foundry is complementary: local metrics make retrieval regressions deterministic; model judges assess the final response. Keep the input records and IDs so a run is auditable, and manually inspect low scores before changing prompts or thresholds.
