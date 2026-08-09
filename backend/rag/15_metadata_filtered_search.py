import os

from dotenv import load_dotenv
from utils_client import get_search_client, get_openai_client
from azure.search.documents.models import VectorizedQuery

load_dotenv()

# -----------------------------
# Clients
# -----------------------------

openai_client = get_openai_client()
search_client = get_search_client()


# -----------------------------
# Query
# -----------------------------

dinosaur = "Triceratops"
section = "Description"

query = "What interesting features did its skull have?"


# -----------------------------
# Embed query
# -----------------------------

embedding_response = openai_client.embeddings.create(
    model=os.environ["AZURE_OPENAI_EMBEDDING_DEPLOYMENT"],
    input=query,
)

query_embedding = embedding_response.data[0].embedding


# -----------------------------
# Vector query
# -----------------------------

vector_query = VectorizedQuery(
    vector=query_embedding,
    k_nearest_neighbors=5,
    fields="embedding",
)


# -----------------------------
# Hybrid + metadata-filtered search
# -----------------------------

results = search_client.search(
    search_text=query,

    vector_queries=[
        vector_query
    ],

    filter=(
        f"dinosaur eq '{dinosaur}' "
        f"and section eq '{section}'"
    ),

    select=[
        "id",
        "dinosaur",
        "section",
        "content",
        "source_url",
    ],

    top=5,
)


# -----------------------------
# Output
# -----------------------------

print("Dinosaur:", dinosaur)
print("Section:", section)
print("Query:", query)

for i, result in enumerate(results, start=1):

    print(f"\n--- Result {i} ---")

    print(
        "ID:",
        result["id"],
    )

    print(
        "Section:",
        result["section"],
    )

    print(
        "Score:",
        result["@search.score"],
    )

    print(
        result["content"][:800]
    )