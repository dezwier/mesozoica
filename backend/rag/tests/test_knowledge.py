from types import SimpleNamespace

from mesozoica_ai.knowledge import (
    AzureSearchKnowledgeStore,
    AzureKnowledgeIndex,
    Embedder,
    EmbeddedChunk,
    KnowledgeBase,
    KnowledgeDocument,
    RecursiveChunker,
    build_filter,
)


class FakeEmbeddings:
    def __init__(self):
        self.documents = []

    def embed_documents(self, texts):
        self.documents.extend(texts)
        return [[float(index), 1.0] for index, _ in enumerate(texts)]

    def embed_query(self, text):
        return [9.0, 1.0]


class FakeStore:
    def __init__(self, hashes=None):
        self.hashes = hashes or {}
        self.uploaded: list[EmbeddedChunk] = []
        self.deleted = []

    def get_content_hashes(self, filters):
        return self.hashes

    def upsert(self, chunks):
        self.uploaded.extend(chunks)

    def delete(self, ids):
        self.deleted.extend(ids)

    def list_ids(self, filters):
        return list(self.hashes)

    def search(self, *, request, query_vector):
        return []


def _document(text="First paragraph.\n\nSecond paragraph."):
    return KnowledgeDocument(
        id="source:1",
        text=text,
        metadata={
            "title": "Title",
            "section": "Section",
            "source": "test",
            "source_id": "1",
        },
    )


def test_chunking_is_deterministic_and_contextualizes_embedding_only():
    chunker = RecursiveChunker(
        chunk_size=20,
        chunk_overlap=2,
        embedding_model="embedding",
        embedding_dimensions=2,
    )
    first = chunker.split([_document()])
    second = chunker.split([_document()])

    assert [chunk.id for chunk in first] == [chunk.id for chunk in second]
    assert first[0].embedding_text.startswith("Title — Section\n\n")
    assert not first[0].text.startswith("Title")


def test_sync_embeds_changed_chunks_and_deletes_stale_chunks():
    chunker = RecursiveChunker(
        chunk_size=100,
        chunk_overlap=0,
        embedding_model="embedding",
        embedding_dimensions=2,
    )
    current = chunker.split([_document("Short text")])[0]
    embeddings = FakeEmbeddings()
    store = FakeStore({current.id: "old-hash", "stale": "hash"})
    from mesozoica_ai.knowledge import Embedder

    knowledge = KnowledgeBase(
        chunker=chunker,
        embedder=Embedder(embeddings, "embedding", 2),
        store=store,
    )

    result = knowledge.sync([_document("Short text")], scope={"source": "test"})

    assert result.embedded_count == 1
    assert result.deleted_count == 1
    assert store.deleted == ["stale"]
    assert store.uploaded[0].content_hash == current.content_hash


def test_filter_builder_escapes_strings_and_rejects_unknown_fields():
    assert build_filter({"source": "author's"}) == "source eq 'author''s'"
    try:
        build_filter({"metadata_json": "unsafe"})
    except ValueError as exc:
        assert "not filterable" in str(exc)
    else:
        raise AssertionError("unknown filter field was accepted")


def test_sync_rejects_empty_or_mismatched_scope_before_store_calls():
    chunker = RecursiveChunker(
        chunk_size=100,
        chunk_overlap=0,
        embedding_model="embedding",
        embedding_dimensions=2,
    )
    knowledge = KnowledgeBase(
        chunker=chunker,
        embedder=Embedder(FakeEmbeddings(), "embedding", 2),
        store=FakeStore(),
    )

    try:
        knowledge.sync([_document()], scope={})
    except ValueError as exc:
        assert "scope" in str(exc)
    else:
        raise AssertionError("empty sync scope was accepted")

    try:
        knowledge.sync([_document()], scope={"source": "different"})
    except ValueError as exc:
        assert "does not match" in str(exc)
    else:
        raise AssertionError("mismatched sync scope was accepted")


def test_azure_store_batches_upserts():
    class Client:
        def __init__(self):
            self.batch_sizes = []

        def upload_documents(self, *, documents):
            self.batch_sizes.append(len(documents))
            return [
                SimpleNamespace(succeeded=True, key=document["id"], error_message=None)
                for document in documents
            ]

    chunk = RecursiveChunker(
        chunk_size=100,
        chunk_overlap=0,
        embedding_model="embedding",
        embedding_dimensions=2,
    ).split([_document("short")])[0]
    embedded = [
        EmbeddedChunk(
            **chunk.model_copy(update={"id": f"chunk-{index}"}).model_dump(),
            embedding=[1.0, 2.0],
        )
        for index in range(3)
    ]
    client = Client()

    AzureSearchKnowledgeStore(client, upload_batch_size=2).upsert(embedded)

    assert client.batch_sizes == [2, 1]


def test_index_definition_is_generic_and_dimensions_are_validated():
    definition = AzureKnowledgeIndex(
        client=None, index_name="knowledge", vector_dimensions=2
    ).definition()
    field_names = {field.name for field in definition.fields}
    assert {"namespace", "subject_id", "source", "updated_at", "embedding"} <= field_names

    class Client:
        def get_index(self, name):
            return definition

    incompatible = AzureKnowledgeIndex(
        client=Client(), index_name="knowledge", vector_dimensions=3
    )
    try:
        incompatible.ensure()
    except RuntimeError as exc:
        assert "dimensions" in str(exc)
    else:
        raise AssertionError("incompatible embedding dimensions were accepted")
