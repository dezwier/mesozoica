import os

from dotenv import load_dotenv
from azure.search.documents.models import VectorizedQuery

from utils_client import get_search_client, get_openai_client


load_dotenv()

# -----------------------------
# Clients
# -----------------------------

openai_client = get_openai_client()
search_client = get_search_client()

def search_knowledge(
    dinosaur: str,
    query: str,
    top_k: int = 5,
):
    # Embed query
    response = openai_client.embeddings.create(
        model=os.environ["AZURE_OPENAI_EMBEDDING_DEPLOYMENT"],
        input=query,
    )

    query_embedding = response.data[0].embedding

    vector_query = VectorizedQuery(
        vector=query_embedding,
        k_nearest_neighbors=top_k,
        fields="embedding",
    )

    # Hybrid search
    results = search_client.search(
        search_text=query,
        vector_queries=[vector_query],
        filter=f"dinosaur eq '{dinosaur}'",
        select=[
            "id",
            "dinosaur",
            "content",
            "source_url",
        ],
        top=top_k,
    )

    return list(results)