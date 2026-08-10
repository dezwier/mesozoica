from types import SimpleNamespace

import pytest

from mesozoica_ai.knowledge import KnowledgeBaseSettings
from mesozoica_ai.knowledge.errors import (
    BatchWriteError, IndexCompatibilityError, InsufficientEvidenceError,
    KnowledgeBaseConfigurationError,
)
from mesozoica_ai.knowledge.models import (
    ChunkState,
    EmbeddedChunk,
    EvidencePolicy,
    KnowledgeDocument,
    RetrievalMode,
    RetrievalRequest,
    RetrievedChunk,
)
from mesozoica_ai.knowledge.tokens import TokenCounter, load_encoding
from mesozoica_ai.knowledge.service import KnowledgeBase
from mesozoica_ai.knowledge.chunking import RecursiveChunker
from mesozoica_ai.knowledge.embeddings import Embedder
from mesozoica_ai.knowledge.index import AzureKnowledgeIndex
from mesozoica_ai.knowledge.store import (
    AzureSearchKnowledgeStore,
    _payload_batches,
    build_filter,
)


class CharacterEncoding:
    name = "characters"

    def encode(self, text, *, disallowed_special=()):
        return [ord(character) for character in text]

    def decode(self, tokens):
        return "".join(chr(token) for token in tokens)


def _counter():
    return TokenCounter("characters", encoding=CharacterEncoding())


class FakeEmbeddings:
    def __init__(self):
        self.documents = []

    def embed_documents(self, texts):
        self.documents.extend(texts)
        return [[float(index), 1.0] for index, _ in enumerate(texts)]

    def embed_query(self, text):
        return [9.0, 1.0]


class FakeStore:
    def __init__(self, states=None, results=None):
        self.states = states or {}
        self.results = results or []
        self.uploaded: list[EmbeddedChunk] = []
        self.merged = []
        self.deleted = []
        self.events = []

    def get_chunk_states(self, filters):
        return self.states

    def upsert(self, chunks):
        self.events.append("upsert")
        self.uploaded.extend(chunks)

    def merge_metadata(self, chunks):
        self.events.append("merge")
        self.merged.extend(chunks)

    def delete(self, ids):
        self.events.append("delete")
        self.deleted.extend(ids)

    def list_ids(self, filters):
        return list(self.states)

    def search(self, *, request, query_vector):
        self.request = request
        self.query_vector = query_vector
        return self.results


def _document(text="First paragraph.\n\nSecond paragraph.", **metadata):
    return KnowledgeDocument(
        id="source:1",
        text=text,
        metadata={
            "title": "Title", "section": "Section", "section_path": ["Body", "Section"],
            "source": "test", "source_id": "1", **metadata,
        },
    )


def _chunker(**kwargs):
    return RecursiveChunker(
        token_counter=_counter(), chunk_size=kwargs.get("chunk_size", 100),
        chunk_overlap=kwargs.get("chunk_overlap", 0), embedding_deployment="embedding",
        embedding_dimensions=2, index_schema_version="2",
    )


def test_exact_token_chunking_is_hierarchical_stable_and_contextualizes_embedding_only():
    chunker = _chunker(chunk_size=20, chunk_overlap=2)
    first = chunker.split([_document()])
    second = chunker.split([_document()])
    assert [chunk.id for chunk in first] == [chunk.id for chunk in second]
    assert first[0].embedding_text.startswith("Title — Body > Section\n\n")
    assert not first[0].text.startswith("Title")
    assert all(_counter().count(chunk.text) <= 20 for chunk in first)


def test_pipeline_fingerprint_changes_with_chunking_or_embedding_configuration():
    assert _chunker(chunk_size=50).pipeline_fingerprint != _chunker(chunk_size=51).pipeline_fingerprint
    other = RecursiveChunker(
        token_counter=_counter(), chunk_size=50, chunk_overlap=0,
        embedding_deployment="new", embedding_dimensions=2, index_schema_version="2",
    )
    assert _chunker(chunk_size=50).pipeline_fingerprint != other.pipeline_fingerprint


def test_settings_validate_cross_field_constraints_and_tokenizer_load_errors():
    values = dict(
        openai_endpoint="https://openai.test", openai_api_key="secret",
        embedding_deployment="embedding", search_endpoint="https://search.test",
        search_query_key="query", search_index="knowledge",
    )
    settings = KnowledgeBaseSettings(_env_file=None, **values)
    assert settings.search_admin_key is None
    with pytest.raises(Exception, match="RAG_CHUNK_OVERLAP"):
        KnowledgeBaseSettings(_env_file=None, **values, chunk_size=10, chunk_overlap=10)
    with pytest.raises(KnowledgeBaseConfigurationError, match="Unable to load"):
        load_encoding("not-a-real-tiktoken-encoding")


def test_sync_distinguishes_embedding_metadata_and_stale_changes_before_deletion():
    chunker = _chunker()
    document = _document("Short text")
    current = chunker.split([document])[0]
    state = ChunkState(
        embedding_hash=current.embedding_hash,
        document_hash="old-metadata-hash",
        pipeline_fingerprint=current.pipeline_fingerprint,
    )
    store = FakeStore({current.id: state, "stale": ChunkState()})
    knowledge = KnowledgeBase(
        chunker=chunker, embedder=Embedder(FakeEmbeddings(), "embedding", 2), store=store,
    )
    result = knowledge.sync([document], scope={"source": "test"})
    assert result.embedded_count == 0
    assert result.metadata_updated_count == 1
    assert result.deleted_count == 1
    assert store.events == ["upsert", "merge", "delete"]


def test_retrieval_modes_and_evidence_policy_deduplicate_and_cap_documents():
    chunks = [
        RetrievedChunk(id="1", document_id="a", text="same", metadata={"source": "x", "source_id": "1", "title": "T"}, score=4),
        RetrievedChunk(id="2", document_id="b", text="same", metadata={"source": "x", "source_id": "2", "title": "T"}, score=3),
        RetrievedChunk(id="3", document_id="a", text="other", metadata={"source": "x", "source_id": "1", "title": "T"}, score=2),
        RetrievedChunk(id="4", document_id="a", text="third", metadata={"source": "x", "source_id": "1", "title": "T"}, score=1),
    ]
    store = FakeStore(results=chunks)
    knowledge = KnowledgeBase(
        chunker=_chunker(), embedder=Embedder(FakeEmbeddings(), "embedding", 2), store=store,
    )
    result = knowledge.retrieve(RetrievalRequest(
        query="query", mode=RetrievalMode.SEMANTIC_HYBRID,
        candidate_k=50, fetch_k=24, top_k=3,
    ))
    assert [chunk.id for chunk in result.chunks] == ["1", "3"]
    assert result.rejection_counts.duplicate_content == 1
    assert result.rejection_counts.per_document_cap == 1
    assert store.query_vector == [9.0, 1.0]


def test_optional_reranker_threshold_can_produce_insufficient_evidence():
    store = FakeStore(results=[RetrievedChunk(
        id="1", document_id="a", text="evidence",
        metadata={"source": "x", "source_id": "1", "title": "T"},
        score=1, reranker_score=1.5,
    )])
    knowledge = KnowledgeBase(
        chunker=_chunker(), embedder=Embedder(FakeEmbeddings(), "embedding", 2), store=store,
    )
    with pytest.raises(InsufficientEvidenceError):
        knowledge.retrieve(RetrievalRequest(
            query="query", candidate_k=50, fetch_k=8, top_k=8,
            evidence_policy=EvidencePolicy(minimum_reranker_score=2),
        ))


def test_filter_builder_escapes_strings_and_rejects_unknown_fields():
    assert build_filter({"source": "author's"}) == "source eq 'author''s'"
    with pytest.raises(ValueError, match="not filterable"):
        build_filter({"metadata_json": "unsafe"})


def test_azure_store_batches_by_count_and_retries_transient_partial_failures():
    class Client:
        def __init__(self):
            self.calls = []

        def upload_documents(self, *, documents):
            self.calls.append([document["id"] for document in documents])
            return [SimpleNamespace(
                succeeded=not (document["id"] == "chunk-1" and len(self.calls) == 1),
                key=document["id"], status_code=503, error_message="transient",
            ) for document in documents]

    chunk = _chunker().split([_document("short")])[0]
    embedded = [EmbeddedChunk(
        **chunk.model_copy(update={"id": f"chunk-{index}"}).model_dump(), embedding=[1, 2]
    ) for index in range(3)]
    client = Client()
    AzureSearchKnowledgeStore(
        query_client=client, write_client=client, write_batch_size=2,
        write_batch_bytes=1_000_000, sleeper=lambda _: None, jitter=lambda: 0,
    ).upsert(embedded)
    assert client.calls == [["chunk-0", "chunk-1"], ["chunk-1"], ["chunk-2"]]


def test_payload_batching_respects_estimated_bytes_as_well_as_count():
    documents = [{"id": str(index), "content": "x" * 80} for index in range(3)]
    batches = list(_payload_batches(documents, max_count=10, max_bytes=150))
    assert [len(batch) for batch in batches] == [1, 1, 1]
    with pytest.raises(BatchWriteError, match="payload_too_large"):
        list(_payload_batches([{"id": "large", "content": "x" * 200}],
                              max_count=10, max_bytes=100))


@pytest.mark.parametrize(
    ("mode", "uses_text", "uses_vector"),
    [
        (RetrievalMode.KEYWORD, True, False),
        (RetrievalMode.VECTOR, False, True),
        (RetrievalMode.HYBRID, True, True),
        (RetrievalMode.SEMANTIC_HYBRID, True, True),
    ],
)
def test_azure_store_executes_each_mode_without_fallback(mode, uses_text, uses_vector):
    class Client:
        def search(self, **kwargs): self.kwargs = kwargs; return []

    client = Client()
    store = AzureSearchKnowledgeStore(query_client=client, write_client=None)
    request = RetrievalRequest(
        query="query", mode=mode, candidate_k=50, fetch_k=24, top_k=8
    )
    store.search(request=request, query_vector=[1, 2] if uses_vector else None)
    assert (client.kwargs["search_text"] is not None) is uses_text
    assert (client.kwargs["vector_queries"] is not None) is uses_vector
    assert client.kwargs["top"] == 24
    if uses_vector:
        assert client.kwargs["vector_queries"][0].k_nearest_neighbors == 50
    if mode == RetrievalMode.SEMANTIC_HYBRID:
        assert client.kwargs["query_type"] == "semantic"


def test_index_definition_is_generic_typed_and_dimensions_are_validated():
    definition = AzureKnowledgeIndex(None, "knowledge", vector_dimensions=2).definition()
    fields = {field.name: field for field in definition.fields}
    assert {"pipeline_fingerprint", "document_hash", "embedding_hash"} <= set(fields)
    assert fields["updated_at"].type.value == "Edm.DateTimeOffset"

    class Client:
        def get_index(self, name):
            return definition

    with pytest.raises(IndexCompatibilityError, match="dimensions"):
        AzureKnowledgeIndex(Client(), "knowledge", vector_dimensions=3).ensure()
