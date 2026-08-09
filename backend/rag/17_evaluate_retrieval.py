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
# Evaluation dataset
# -----------------------------

test_cases = [
    {
        "query": "What did the skull and horns of Triceratops look like?",
        "expected_section": "Description",
    },
    {
        "query": "What evidence suggests Triceratops fought other members of its species?",
        "expected_section": "Paleobiology",
    },
    {
        "query": "How was Triceratops discovered and named?",
        "expected_section": "Discovery and identification",
    },
    {
        "query": "How is Triceratops classified among ceratopsians?",
        "expected_section": "Classification",
    },
]


dinosaur = "Triceratops"
top_k = 5


# -----------------------------
# Run evaluation
# -----------------------------

hits = 0


for test in test_cases:

    query = test["query"]
    expected_section = test["expected_section"]

    # Embed query
    embedding_response = openai_client.embeddings.create(
        model=os.environ["AZURE_OPENAI_EMBEDDING_DEPLOYMENT"],
        input=query,
    )

    query_embedding = embedding_response.data[0].embedding

    vector_query = VectorizedQuery(
        vector=query_embedding,
        k_nearest_neighbors=top_k,
        fields="embedding",
    )

    # Hybrid search
    results = list(
        search_client.search(
            search_text=query,
            vector_queries=[vector_query],
            filter=f"dinosaur eq '{dinosaur}'",
            select=[
                "id",
                "section",
                "content",
            ],
            top=top_k,
        )
    )

    returned_sections = [
        result["section"]
        for result in results
    ]

    success = expected_section in returned_sections

    if success:
        hits += 1

    print("\n================================")
    print("QUERY")
    print(query)

    print("\nEXPECTED SECTION")
    print(expected_section)

    print("\nRETURNED SECTIONS")
    for i, section in enumerate(
        returned_sections,
        start=1,
    ):
        print(f"{i}. {section}")

    print("\nHIT:", success)


# -----------------------------
# Final metric
# -----------------------------

recall_at_k = hits / len(test_cases)

print("\n================================")
print("FINAL RESULT")
print("================================")

print(
    f"Recall@{top_k}: "
    f"{hits}/{len(test_cases)} "
    f"= {recall_at_k:.2%}"
)