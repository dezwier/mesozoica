from __future__ import annotations

from collections import Counter

from azure.search.documents import SearchClient


class KnowledgeInspector:
    """Read-only operational summary for one configured knowledge index."""

    def __init__(self, client: SearchClient) -> None:
        self.client = client

    def overview(self) -> dict:
        """Count chunks by scope/source and report represented pipeline fingerprints."""
        results = self.client.search(
            search_text="*",
            select=["namespace", "subject_id", "source", "pipeline_fingerprint"],
        )
        namespaces: Counter[str] = Counter()
        subjects: Counter[str] = Counter()
        sources: Counter[str] = Counter()
        fingerprints: Counter[str] = Counter()
        for result in results:
            if result.get("namespace"):
                namespaces[result["namespace"]] += 1
            if result.get("subject_id"):
                subjects[result["subject_id"]] += 1
            if result.get("source"):
                sources[result["source"]] += 1
            if result.get("pipeline_fingerprint"):
                fingerprints[result["pipeline_fingerprint"]] += 1
        return {
            "chunks": self.client.get_document_count(),
            "namespaces": namespaces,
            "subjects": subjects,
            "sources": sources,
            "pipeline_fingerprints": fingerprints,
        }
