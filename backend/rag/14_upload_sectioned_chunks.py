import os

from dotenv import load_dotenv
from utils_client import get_search_client, get_openai_client
from utils_ingestion import load_wikipedia_sections, chunk_sections


load_dotenv()

# -----------------------------
# Clients
# -----------------------------

openai_client = get_openai_client()
search_client = get_search_client()

dinosaur = "Triceratops"

# -----------------------------
# Delete old Triceratops chunks
# -----------------------------

old_results = search_client.search(
    search_text="*",
    filter=f"dinosaur eq '{dinosaur}'",
    select=["id"],
    top=1000,
)

old_documents = [
    {"id": result["id"]}
    for result in old_results
]

if old_documents:
    search_client.delete_documents(
        documents=old_documents
    )

    print(
        f"Deleted {len(old_documents)} old documents"
    )

# -----------------------------
# Load section-aware chunks
# -----------------------------

docs = load_wikipedia_sections(dinosaur)
chunks = chunk_sections(docs)

print("Chunks:", len(chunks))


# -----------------------------
# Embed chunks
# -----------------------------

texts = [
    chunk.page_content
    for chunk in chunks
]

embedding_response = openai_client.embeddings.create(
    model=os.environ["AZURE_OPENAI_EMBEDDING_DEPLOYMENT"],
    input=texts,
)

vectors = [
    item.embedding
    for item in embedding_response.data
]

print("Embeddings:", len(vectors))


# -----------------------------
# Build Azure documents
# -----------------------------

documents = []

for chunk, vector in zip(chunks, vectors):

    document = {
        "id": chunk.metadata["chunk_id"],
        "dinosaur": chunk.metadata["dinosaur"],
        "section": chunk.metadata["section"],
        "content": chunk.page_content,
        "source_url": chunk.metadata["source_url"],
        "embedding": vector,
    }

    documents.append(document)


# -----------------------------
# Upload
# -----------------------------

results = search_client.upload_documents(
    documents=documents
)

successful = sum(
    result.succeeded
    for result in results
)

print(
    f"Uploaded: {successful}/{len(results)}"
)


# -----------------------------
# Verify some metadata
# -----------------------------

results = search_client.search(
    search_text="*",
    filter="dinosaur eq 'Triceratops'",
    select=[
        "id",
        "dinosaur",
        "section",
        "content",
    ],
    top=10,
)

print("\nINDEXED DOCUMENTS")

for result in results:

    print("\n--------------------")

    print(
        "ID:",
        result["id"],
    )

    print(
        "Section:",
        result["section"],
    )

    print(
        result["content"][:200]
    )