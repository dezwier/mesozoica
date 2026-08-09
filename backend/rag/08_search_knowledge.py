import os

from dotenv import load_dotenv
from azure.search.documents.models import VectorizedQuery

from utils_client import get_search_client, get_openai_client


load_dotenv()

openai_client = get_openai_client()
search_client = get_search_client()


query = "What was unusual about the skull of Triceratops?"


# 1. Embed the question
response = openai_client.embeddings.create(
    model=os.environ["AZURE_OPENAI_EMBEDDING_DEPLOYMENT"],
    input=query,
)

query_embedding = response.data[0].embedding


# 2. Describe the vector search
vector_query = VectorizedQuery(
    vector=query_embedding,
    k_nearest_neighbors=5,
    fields="embedding",
)


# 3. Search Azure AI Search
results = search_client.search(
    search_text=query,
    vector_queries=[vector_query],
    filter="dinosaur eq 'Triceratops'",
    select=[
        "id",
        "dinosaur",
        "content",
        "source_url",
    ],
    top=5,
)


# 4. Inspect results
for i, result in enumerate(results, start=1):
    print(f"\n--- Result {i} ---")
    print("ID:", result["id"])
    print("Score:", result["@search.score"])
    print(result["content"][:800])