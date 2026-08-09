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

query = (
    "What evidence suggests that Triceratops "
    "used its horns in combat?"
)


# -----------------------------
# Embed query
# -----------------------------

embedding_response = openai_client.embeddings.create(
    model=os.environ["AZURE_OPENAI_EMBEDDING_DEPLOYMENT"],
    input=query,
)

query_embedding = embedding_response.data[0].embedding


vector_query = VectorizedQuery(
    vector=query_embedding,

    # Retrieve a broader candidate set.
    k_nearest_neighbors=20,

    fields="embedding",
)


# -----------------------------
# Hybrid + semantic search
# -----------------------------

results = search_client.search(
    search_text=query,

    vector_queries=[
        vector_query
    ],

    filter=f"dinosaur eq '{dinosaur}'",

    # NEW:
    query_type="semantic",

    semantic_configuration_name=(
        "semantic-config"
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
        "Search score:",
        result["@search.score"],
    )

    print(
        "Semantic reranker score:",
        result.get(
            "@search.reranker_score"
        ),
    )

    print(
        result["content"][:800]
    )