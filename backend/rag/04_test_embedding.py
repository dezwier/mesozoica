import os

from dotenv import load_dotenv
from utils_client import get_openai_client

load_dotenv()

client = get_openai_client()

response = client.embeddings.create(
    model=os.environ["AZURE_OPENAI_EMBEDDING_DEPLOYMENT"],
    input="Triceratops had a large skull and three facial horns.",
)

embedding = response.data[0].embedding

print("Deployment:", os.environ["AZURE_OPENAI_EMBEDDING_DEPLOYMENT"])
print("Dimensions:", len(embedding))
print("First 5:", embedding[:5])