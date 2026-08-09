import os

from dotenv import load_dotenv

from utils_ingestion import load_dinosaur, chunk_documents
from utils_client import get_search_client, get_openai_client


load_dotenv()

openai_client = get_openai_client()

# Azure Search client
search_client = get_search_client()

# Load + chunk
docs = load_dinosaur("Triceratops")
chunks = chunk_documents(docs)

print(f"Chunks: {len(chunks)}")

# Embed all chunk texts in one request/batch
texts = [chunk.page_content for chunk in chunks]

response = openai_client.embeddings.create(
    model=os.environ["AZURE_OPENAI_EMBEDDING_DEPLOYMENT"],
    input=texts,
)

vectors = [item.embedding for item in response.data]

print(f"Embeddings: {len(vectors)}")
print(f"Dimensions: {len(vectors[0])}")

# Build Azure Search documents
documents = []

for chunk, vector in zip(chunks, vectors):
    documents.append(
        {
            "id": chunk.metadata["chunk_id"],
            "dinosaur": chunk.metadata["dinosaur"],
            "section": "",
            "content": chunk.page_content,
            "source_url": chunk.metadata["source_url"],
            "embedding": vector,
        }
    )

# Upload
results = search_client.upload_documents(
    documents=documents
)

successful = sum(r.succeeded for r in results)

print(f"Uploaded: {successful}/{len(results)}")

for result in results:
    if not result.succeeded:
        print(result.key, result.error_message)