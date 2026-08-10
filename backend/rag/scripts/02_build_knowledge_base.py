"""Retrieve one Wikipedia subject and sync it into Azure Search."""

import os

from dotenv import load_dotenv

from mesozoica_ai import AiConfig, ensure_index, retrieve_wikipedia, sync_documents

load_dotenv()

TITLE = "Triceratops"
SUBJECT_ID = f"animal:{TITLE.casefold()}"
SCOPE = {"namespace": "example", "subject_id": SUBJECT_ID, "source": "wikipedia"}

config = AiConfig()
documents = retrieve_wikipedia(
    TITLE,
    user_agent=os.environ["WIKIPEDIA_USER_AGENT"],
    metadata={"namespace": "example", "subject_id": SUBJECT_ID},
)
ensure_index(config=config)
print(sync_documents(documents, scope=SCOPE, config=config).model_dump_json(indent=2))
