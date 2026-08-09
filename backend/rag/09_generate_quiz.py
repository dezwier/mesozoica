import os

from dotenv import load_dotenv
from pydantic import BaseModel
from utils_client import get_search_client, get_openai_client
from azure.search.documents.models import VectorizedQuery


load_dotenv()


# -----------------------------
# Clients
# -----------------------------

openai_client = get_openai_client()
search_client = get_search_client()

# -----------------------------
# Output schema
# -----------------------------

class QuizQuestion(BaseModel):
    question: str
    options: list[str]
    correct_index: int
    explanation: str
    source_chunk_ids: list[str]


# -----------------------------
# Retrieve knowledge
# -----------------------------

dinosaur = "Triceratops"

retrieval_query = (
    "Interesting and distinctive facts about Triceratops "
    "suitable for a multiple-choice quiz"
)

embedding_response = openai_client.embeddings.create(
    model=os.environ["AZURE_OPENAI_EMBEDDING_DEPLOYMENT"],
    input=retrieval_query,
)

query_embedding = embedding_response.data[0].embedding

vector_query = VectorizedQuery(
    vector=query_embedding,
    k_nearest_neighbors=5,
    fields="embedding",
)

results = list(
    search_client.search(
        search_text=None,
        vector_queries=[vector_query],
        filter=f"dinosaur eq '{dinosaur}'",
        select=[
            "id",
            "content",
            "source_url",
        ],
        top=5,
    )
)


# -----------------------------
# Build RAG context
# -----------------------------

context_parts = []

for result in results:
    context_parts.append(
        f"""
CHUNK ID: {result["id"]}
SOURCE: {result["source_url"]}
CONTENT:
{result["content"]}
""".strip()
    )

context = "\n\n---\n\n".join(context_parts)


# -----------------------------
# Generate quiz
# -----------------------------

prompt = f"""
You create scientifically grounded dinosaur quiz questions.

DINOSAUR:
{dinosaur}

RETRIEVED KNOWLEDGE:
{context}

TASK:
Create exactly one interesting multiple-choice question about {dinosaur}.

Rules:
- Use only facts supported by the retrieved knowledge.
- Make the question interesting rather than trivial.
- Provide exactly 4 answer options.
- Exactly one option must be correct.
- correct_index must be 0, 1, 2, or 3.
- Give a short explanation of why the answer is correct.
- Include the chunk ID(s) that support the correct answer.
"""


response = openai_client.responses.parse(
    model=os.environ["AZURE_OPENAI_CHAT_DEPLOYMENT"],
    input=prompt,
    text_format=QuizQuestion,
)


quiz = response.output_parsed


# -----------------------------
# Show result
# -----------------------------

print("\nQUESTION")
print(quiz.question)

print("\nOPTIONS")
for i, option in enumerate(quiz.options):
    marker = "*" if i == quiz.correct_index else " "
    print(f"{marker} {i}: {option}")

print("\nEXPLANATION")
print(quiz.explanation)

print("\nSOURCE CHUNKS")
for chunk_id in quiz.source_chunk_ids:
    print("-", chunk_id)