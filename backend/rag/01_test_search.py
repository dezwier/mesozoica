import os

from dotenv import load_dotenv
from azure.core.credentials import AzureKeyCredential
from azure.search.documents.indexes import SearchIndexClient


load_dotenv()

endpoint = os.environ["AZURE_SEARCH_ENDPOINT"]
api_key = os.environ["AZURE_SEARCH_API_KEY"]


client = SearchIndexClient(
    endpoint=endpoint,
    credential=AzureKeyCredential(api_key),
)


print(f"Connected to: {endpoint}")
print("Existing indexes:")

for index in client.list_indexes():
    print(f"- {index.name}")