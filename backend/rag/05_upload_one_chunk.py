import os

from dotenv import load_dotenv

from utils_client import get_openai_client, get_search_client
from utils_ingestion import load_dinosaur, chunk_documents


load_dotenv()


# --- OpenAI embedding client ---
openai_client = get_openai_client()


# --- Azure AI Search client ---
search_client = get_search_client()


# --- Load + chunk Triceratops ---
docs = load_dinosaur("Triceratops")
chunks = chunk_documents(docs)

chunk = chunks[0]

print("Chunk ID:", chunk.metadata["chunk_id"])
print("Chunk text:")
print(chunk.page_content[:500])


# --- Embed this one chunk ---

response = openai_client.embeddings.create(
    model=os.environ["AZURE_OPENAI_EMBEDDING_DEPLOYMENT"],
    input=chunk.page_content,
)

embedding = response.data[0].embedding

print("Embedding dimensions:", len(embedding))


# --- Convert it to the Azure Search schema ---

document = {
    "id": chunk.metadata["chunk_id"],
    "dinosaur": chunk.metadata["dinosaur"],
    "section": "",
    "content": chunk.page_content,
    "source_url": chunk.metadata["source_url"],
    "embedding": embedding,
}


# --- Upload ---

results = search_client.upload_documents(
    documents=[document]
)

for result in results:
    print(
        "Uploaded:",
        result.key,
        "success:",
        result.succeeded,
    )

    if not result.succeeded:
        print("Error:", result.error_message)