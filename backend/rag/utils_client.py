import os
from openai import OpenAI
from azure.core.credentials import AzureKeyCredential
from azure.search.documents import SearchClient


def get_openai_client():
    base_url = (
        os.environ["AZURE_OPENAI_ENDPOINT"].rstrip("/")
        + "/openai/v1/"
    )

    return OpenAI(
        api_key=os.environ["AZURE_OPENAI_API_KEY"],
        base_url=base_url,
    )


def get_search_client():
    return SearchClient(
        endpoint=os.environ["AZURE_SEARCH_ENDPOINT"],
        index_name="dinosaur-knowledge",
        credential=AzureKeyCredential(
            os.environ["AZURE_SEARCH_API_KEY"]
        ),
    )