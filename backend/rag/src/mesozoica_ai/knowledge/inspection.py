from collections import Counter

from azure.search.documents import SearchClient


class KnowledgeInspector:
    def __init__(self, client: SearchClient):
        self.client = client

    def overview(self) -> dict:
        results = list(
            self.client.search(
                search_text="*",
                select=[
                    "source_id",
                    "dinosaur",
                    "section",
                ],
                top=1000,
            )
        )

        return {
            "chunks": self.client.get_document_count(),
            "sources": Counter(
                r.get("source_id")
                for r in results
                if r.get("source_id")
            ),
            "dinosaurs": Counter(
                r.get("dinosaur")
                for r in results
                if r.get("dinosaur")
            ),
            "sections": Counter(
                r.get("section")
                for r in results
                if r.get("section")
            ),
        }