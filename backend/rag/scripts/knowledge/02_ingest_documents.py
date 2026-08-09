import re
import requests

from mesozoica_ai.knowledge import (
    KnowledgeDocument,
    KnowledgeSettings,
    create_knowledge_base,
    create_knowledge_index,
)


WIKIPEDIA_API = "https://en.wikipedia.org/w/api.php"


def load_wikipedia_dinosaur(
    dinosaur: str,
) -> list[KnowledgeDocument]:

    response = requests.get(
        WIKIPEDIA_API,
        params={
            "action": "query",
            "prop": "extracts",
            "explaintext": True,
            "redirects": True,
            "titles": dinosaur,
            "format": "json",
            "formatversion": 2,
        },
        headers={
            "User-Agent": "Mesozoica/1.0"
        },
        timeout=20,
    )

    response.raise_for_status()

    page = response.json()["query"]["pages"][0]

    if page.get("missing"):
        raise ValueError(
            f"Wikipedia page not found: {dinosaur}"
        )

    title = page["title"]
    text = page["extract"]

    dinosaur_slug = re.sub(
        r"[^a-z0-9]+",
        "-",
        dinosaur.lower(),
    ).strip("-")

    source_id = f"wikipedia:{dinosaur_slug}"

    source_url = (
        "https://en.wikipedia.org/wiki/"
        + title.replace(" ", "_")
    )

    parts = re.split(
        r"(?m)^==+\s*(.*?)\s*==+\s*$",
        text,
    )

    sections = [
        ("Introduction", parts[0]),
        *zip(parts[1::2], parts[2::2]),
    ]

    documents = []

    for section, content in sections:
        content = content.strip()

        if not content:
            continue

        section_slug = re.sub(
            r"[^a-z0-9]+",
            "-",
            section.lower(),
        ).strip("-")

        documents.append(
            KnowledgeDocument(
                id=f"{dinosaur_slug}-{section_slug}",
                text=content,
                metadata={
                    "source_id": source_id,
                    "dinosaur": dinosaur,
                    "section": section,
                    "source_url": source_url,
                },
            )
        )

    return documents


dinosaur = "Spinosaurus"

settings = KnowledgeSettings()

create_knowledge_index(settings).ensure()

knowledge = create_knowledge_base(settings)

documents = load_wikipedia_dinosaur(dinosaur)

result = knowledge.sync(
    documents,
    scope={"source_id": f"wikipedia:{dinosaur.lower()}"},
)

print(f"Documents: {result.document_count}")
print(f"Chunks: {result.chunk_count}")
print(f"Embedded: {result.embedded_count}")
print(f"Skipped unchanged: {result.skipped_count}")
print(f"Deleted stale: {result.deleted_count}")
