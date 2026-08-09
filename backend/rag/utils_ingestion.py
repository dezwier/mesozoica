from langchain_core.documents import Document
from langchain_text_splitters import RecursiveCharacterTextSplitter
import requests
import time
from bs4 import BeautifulSoup

WIKIPEDIA_API = "https://en.wikipedia.org/w/api.php"
HEADERS = {
    "User-Agent": "Mesosoica/0.1 dinosaur-rag-learning"
}

def load_dinosaur(dinosaur: str) -> list[Document]:
    params = {
        "action": "query",
        "prop": "extracts",
        "explaintext": True,
        "redirects": True,
        "titles": dinosaur,
        "format": "json",
        "formatversion": 2,
    }

    response = requests.get(
        WIKIPEDIA_API,
        params=params,
        timeout=20,
        headers={
            "User-Agent": "Mesosoica/0.1 dinosaur-rag-learning"
        },
    )
    response.raise_for_status()

    data = response.json()

    page = data["query"]["pages"][0]

    if page.get("missing"):
        raise ValueError(f"Wikipedia page not found: {dinosaur}")

    text = page["extract"]
    title = page["title"]

    document = Document(
        page_content=text,
        metadata={
            "dinosaur": dinosaur,
            "title": title,
            "source_type": "wikipedia",
            "source_url": f"https://en.wikipedia.org/wiki/{title.replace(' ', '_')}",
        },
    )

    return [document]


def chunk_documents(docs: list[Document]) -> list[Document]:
    splitter = RecursiveCharacterTextSplitter(
        chunk_size=1000,
        chunk_overlap=150,
    )

    chunks = splitter.split_documents(docs)

    for i, chunk in enumerate(chunks):
        slug = chunk.metadata["dinosaur"].lower().replace(" ", "-")
        chunk.metadata["chunk_id"] = f"{slug}-{i:04d}"

    return chunks

def get_with_retry(
    url: str,
    params: dict,
    headers: dict,
    max_retries: int = 5,
):
    for attempt in range(max_retries):
        response = requests.get(
            url,
            params=params,
            timeout=20,
            headers=headers,
        )

        if response.status_code != 429:
            response.raise_for_status()
            return response

        retry_after = response.headers.get("Retry-After")

        if retry_after:
            wait_seconds = int(retry_after)
        else:
            wait_seconds = 5 * (attempt + 1)

        print(
            f"Rate limited by Wikipedia. "
            f"Waiting {wait_seconds}s..."
        )

        time.sleep(wait_seconds)

    raise RuntimeError(
        "Wikipedia rate limit persisted after retries"
    )


def load_wikipedia_sections(
    dinosaur: str,
) -> list[Document]:

    # --------------------------------
    # 1. Get the list of sections
    # --------------------------------

    section_response = get_with_retry(
        WIKIPEDIA_API,
        params={
            "action": "parse",
            "page": dinosaur,
            "prop": "sections",
            "format": "json",
        },
        headers=HEADERS,
    )

    data = section_response.json()

    sections = data["parse"]["sections"]

    documents = []

    # Section 0 is the article introduction
    section_items = [
        {
            "index": "0",
            "title": "Introduction",
        }
    ]

    # Add all Wikipedia sections
    for section in sections:
        section_items.append(
            {
                "index": section["index"],
                "title": section["line"],
            }
        )

    print(
        f"Found {len(section_items)} sections "
        f"for {dinosaur}"
    )


    # --------------------------------
    # 2. Retrieve each section
    # --------------------------------

    for section in section_items:

        print(
            f"Fetching section "
            f"{section['index']}: "
            f"{section['title']}"
        )

        response = get_with_retry(
            WIKIPEDIA_API,
            params={
                "action": "parse",
                "page": dinosaur,
                "prop": "text",
                "section": section["index"],
                "format": "json",
                "formatversion": 2,
            },
            headers=HEADERS,
        )

        html = response.json()["parse"]["text"]

        # Convert HTML to plain text
        text = BeautifulSoup(
            html,
            "html.parser",
        ).get_text(
            " ",
            strip=True,
        )

        if not text:
            continue

        documents.append(
            Document(
                page_content=text,
                metadata={
                    "dinosaur": dinosaur,
                    "section": section["title"],
                    "source_url": (
                        "https://en.wikipedia.org/wiki/"
                        + dinosaur.replace(" ", "_")
                    ),
                },
            )
        )

        # Be polite to Wikipedia
        time.sleep(0.3)

    return documents


def chunk_sections(
    docs: list[Document],
) -> list[Document]:

    splitter = RecursiveCharacterTextSplitter(
        chunk_size=1000,
        chunk_overlap=150,
    )

    chunks = []

    # Important:
    # split each section independently
    # so chunks never cross section boundaries
    for doc in docs:

        section_chunks = splitter.split_documents(
            [doc]
        )

        chunks.extend(section_chunks)

    # Assign stable IDs
    for i, chunk in enumerate(chunks):

        slug = (
            chunk.metadata["dinosaur"]
            .lower()
            .replace(" ", "-")
        )

        chunk.metadata["chunk_id"] = (
            f"{slug}-{i:04d}"
        )

    return chunks
