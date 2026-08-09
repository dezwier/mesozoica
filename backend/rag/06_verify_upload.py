import os
import time

from dotenv import load_dotenv
from utils_client import get_search_client

load_dotenv()

client = get_search_client()


# Give indexing a moment
time.sleep(2)

print("Document count:", client.get_document_count())

results = client.search(
    search_text="*",
    top=5,
    select=["id", "dinosaur", "content", "source_url"],
)

for result in results:
    print("\nID:", result["id"])
    print("Dinosaur:", result["dinosaur"])
    print("Content:", result["content"][:200])