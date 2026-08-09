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
    difficulty: str
    options: list[str]
    correct_index: int
    explanation: str
    source_chunk_ids: list[str]


# -----------------------------
# User context
# -----------------------------

dinosaur = "Triceratops"

user = {
    "language": "English",
    "knowledge_level": "expert",
    "preferred_difficulty": "hard",
}

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


previous_topics = [q["topic"] for q in previous_questions]


# -----------------------------
# Retrieval
# -----------------------------

retrieval_query = f"""
Interesting distinctive facts about {dinosaur} suitable for a
{user["knowledge_level"]} dinosaur enthusiast.

Avoid these topics:
{", ".join(previous_topics)}

Prefer facts with enough detail to support a
{user["preferred_difficulty"]} difficulty multiple-choice question.
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
        select=["id", "content", "source_url"],
        top=8,
    )
)


# -----------------------------
# Build context
# -----------------------------

context = "\n\n---\n\n".join(
    f"""
CHUNK ID: {result["id"]}
CONTENT:
{result["content"]}
""".strip()
    for result in results
)

history_text = "\n".join(
    f"- Topic: {item['topic']} | Question: {item['question']}"
    for item in previous_questions
)


# -----------------------------
# Generate personalized quiz
# -----------------------------

prompt = f"""
You create scientifically grounded dinosaur quiz questions.

DINOSAUR:
{dinosaur}

USER:
Language: {user["language"]}
Knowledge level: {user["knowledge_level"]}
Preferred difficulty: {user["preferred_difficulty"]}

PREVIOUS QUESTIONS:
{history_text}

RETRIEVED KNOWLEDGE:
{context}

TASK:
Create exactly one new multiple-choice question.

Rules:
- Write the question and explanation in {user["language"]}.
- Match the user's {user["knowledge_level"]} knowledge level.
- Target {user["preferred_difficulty"]} difficulty.
- Do not repeat previous topics.
- Use only facts supported by the retrieved knowledge.
- Prefer an interesting fact over a trivial fact.
- Provide exactly 4 options.
- Exactly one answer must be correct.
- correct_index must be 0, 1, 2, or 3.
- topic must be a short descriptive label.
- difficulty must be one of: easy, medium, hard.
- Include the supporting chunk ID(s).
"""


response = openai_client.responses.parse(
    model=os.environ["AZURE_OPENAI_CHAT_DEPLOYMENT"],
    input=prompt,
    text_format=QuizQuestion,
)

quiz = response.output_parsed


# -----------------------------
# Output
# -----------------------------

print("\nUSER")
print(user)

print("\nTOPIC")
print(quiz.topic)

print("\nDIFFICULTY")
print(quiz.difficulty)

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