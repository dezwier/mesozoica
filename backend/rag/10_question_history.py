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
    topic: str
    options: list[str]
    correct_index: int
    explanation: str
    source_chunk_ids: list[str]


# -----------------------------
# Application state
# -----------------------------

dinosaur = "Triceratops"

previous_questions = [
    {
        "question": "How many facial horns did Triceratops have?",
        "topic": "horn count",
    },
    {
        "question": "What did Triceratops mainly eat?",
        "topic": "diet",
    },
    {
        "question": "During which geological period did Triceratops live?",
        "topic": "geological age",
    },
]


previous_topics = [
    item["topic"]
    for item in previous_questions
]

print("Already covered topics:")
for topic in previous_topics:
    print("-", topic)


# -----------------------------
# Retrieval query
# -----------------------------

retrieval_query = f"""
Interesting distinctive facts about {dinosaur} suitable for a quiz.

Avoid these already-covered topics:
{", ".join(previous_topics)}

Prefer anatomy, behavior, growth, unusual adaptations,
fossil evidence, or other interesting facts.
"""


embedding_response = openai_client.embeddings.create(
    model=os.environ["AZURE_OPENAI_EMBEDDING_DEPLOYMENT"],
    input=retrieval_query,
)

query_embedding = embedding_response.data[0].embedding

vector_query = VectorizedQuery(
    vector=query_embedding,
    k_nearest_neighbors=8,
    fields="embedding",
)

results = list(
    search_client.search(
        search_text=retrieval_query,
        vector_queries=[vector_query],
        filter=f"dinosaur eq '{dinosaur}'",
        select=[
            "id",
            "content",
            "source_url",
        ],
        top=8,
    )
)


# -----------------------------
# Build retrieved context
# -----------------------------

context_parts = []

for result in results:
    context_parts.append(
        f"""
CHUNK ID: {result["id"]}
CONTENT:
{result["content"]}
""".strip()
    )

context = "\n\n---\n\n".join(context_parts)


# -----------------------------
# Generate a NEW quiz question
# -----------------------------

history_text = "\n".join(
    f"- Topic: {item['topic']} | Question: {item['question']}"
    for item in previous_questions
)


prompt = f"""
You create scientifically grounded dinosaur quiz questions.

DINOSAUR:
{dinosaur}

PREVIOUS QUESTIONS:
{history_text}

RETRIEVED KNOWLEDGE:
{context}

TASK:
Create exactly one new multiple-choice question about {dinosaur}.

Rules:
- Do NOT repeat or closely paraphrase any previous question.
- Do NOT use any already-covered topic.
- Choose a genuinely different fact.
- Use only facts supported by the retrieved knowledge.
- Provide exactly 4 answer options.
- Exactly one option must be correct.
- correct_index must be 0, 1, 2, or 3.
- topic should be a short label describing what the question tests.
- Give a short explanation.
- Include the chunk ID(s) supporting the answer.
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

print("\nNEW TOPIC")
print(quiz.topic)

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