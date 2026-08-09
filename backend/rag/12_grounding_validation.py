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
# Schemas
# -----------------------------

class QuizQuestion(BaseModel):
    question: str
    topic: str
    difficulty: str
    options: list[str]
    correct_index: int
    explanation: str
    source_chunk_ids: list[str]


class GroundingResult(BaseModel):
    grounded: bool
    confidence: float
    reason: str
    supporting_chunk_ids: list[str]


# -----------------------------
# Context
# -----------------------------

dinosaur = "Triceratops"

user = {
    "language": "English",
    "knowledge_level": "intermediate",
    "preferred_difficulty": "medium",
}

previous_topics = [
    "horn count",
    "diet",
    "geological age",
]


# -----------------------------
# Retrieve
# -----------------------------

retrieval_query = f"""
Interesting distinctive facts about {dinosaur}
for a {user["preferred_difficulty"]} multiple-choice quiz.

Avoid:
{", ".join(previous_topics)}
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

context = "\n\n---\n\n".join(
    f"""
CHUNK ID: {r["id"]}
CONTENT:
{r["content"]}
""".strip()
    for r in results
)


# -----------------------------
# Generate
# -----------------------------

generation_prompt = f"""
Create one scientifically grounded multiple-choice quiz question.

DINOSAUR:
{dinosaur}

USER:
Knowledge level: {user["knowledge_level"]}
Difficulty: {user["preferred_difficulty"]}
Language: {user["language"]}

AVOID TOPICS:
{", ".join(previous_topics)}

RETRIEVED KNOWLEDGE:
{context}

Rules:
- Use only the retrieved knowledge.
- Provide exactly 4 options.
- Exactly one option must be correct.
- correct_index must be 0-3.
- Do not use an avoided topic.
- Include supporting chunk IDs.
"""

generation_response = openai_client.responses.parse(
    model=os.environ["AZURE_OPENAI_CHAT_DEPLOYMENT"],
    input=generation_prompt,
    text_format=QuizQuestion,
)

quiz = generation_response.output_parsed


# -----------------------------
# Validate grounding
# -----------------------------

correct_answer = quiz.options[quiz.correct_index]

validation_prompt = f"""
You are validating whether a generated dinosaur quiz is grounded
in the supplied evidence.

QUESTION:
{quiz.question}

CORRECT ANSWER:
{correct_answer}

EXPLANATION:
{quiz.explanation}

EVIDENCE:
{context}

Determine whether the question, correct answer, and explanation
are directly supported by the evidence.

Rules:
- Do not use outside knowledge.
- grounded=true only if the essential factual claim is supported.
- confidence must be between 0 and 1.
- supporting_chunk_ids must contain only chunk IDs from the evidence.
- If evidence is ambiguous, incomplete, or contradictory, grounded=false.
"""

validation_response = openai_client.responses.parse(
    model=os.environ["AZURE_OPENAI_CHAT_DEPLOYMENT"],
    input=validation_prompt,
    text_format=GroundingResult,
)

validation = validation_response.output_parsed


# -----------------------------
# Output
# -----------------------------

print("\nQUESTION")
print(quiz.question)

print("\nOPTIONS")
for i, option in enumerate(quiz.options):
    marker = "*" if i == quiz.correct_index else " "
    print(f"{marker} {i}: {option}")

print("\nEXPLANATION")
print(quiz.explanation)

print("\nGROUNDING")
print("Grounded:", validation.grounded)
print("Confidence:", validation.confidence)
print("Reason:", validation.reason)

print("\nSUPPORTING CHUNKS")
for chunk_id in validation.supporting_chunk_ids:
    print("-", chunk_id)