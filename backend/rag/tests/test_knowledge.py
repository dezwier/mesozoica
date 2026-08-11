from types import SimpleNamespace
from datetime import datetime, timezone

import pytest

from mesozoica_ai.common import (
    begin_embedding,
    begin_indexing,
    complete_embedding,
    complete_indexing,
    embedding_needed,
    fail_embedding,
    fail_indexing,
    indexing_needed,
    reset_embedding,
    reset_indexing,
)
from mesozoica_ai.common.config import AiConfig as KnowledgeConfig
from mesozoica_ai.common.errors import (
    BatchWriteError,
    IndexCompatibilityError,
    InsufficientEvidenceError,
)
from mesozoica_ai.index import (
    chunk_documents,
    embed_chunks,
    embed_query,
    ensure_index,
    index_chunks,
    pipeline_fingerprint,
    prepare_embeddings,
    recreate_index,
    retrieve_chunks,
    sync_documents,
    sync_embedded_chunks,
)
from mesozoica_ai.index import api as knowledge_api
from mesozoica_ai.index.chunking import RecursiveChunker
from mesozoica_ai.index.embeddings import Embedder
from mesozoica_ai.index.schema import AzureKnowledgeIndex
from mesozoica_ai.index.store import (
    AzureSearchKnowledgeStore,
    _payload_batches,
    build_filter,
)
from mesozoica_ai.common.models import (
    ChunkState,
    EmbeddedChunk,
    EvidencePolicy,
    KnowledgeDocument,
    RetrievalMode,
    RetrievalRequest,
    RetrievedChunk,
)
from mesozoica_ai.common.tokens import TokenCounter, TokenizerError, load_encoding


class CharacterEncoding:
    name = "characters"

    def encode(self, text, *, disallowed_special=()):
        return [ord(character) for character in text]

    def decode(self, tokens):
        return "".join(chr(token) for token in tokens)


def _counter():
    return TokenCounter("characters", encoding=CharacterEncoding())


def _config(**overrides):
    values = {
        "openai_endpoint": "https://openai.test",
        "openai_api_key": "secret",
        "embedding_deployment": "embedding",
        "embedding_dimensions": 2,
        "search_endpoint": "https://search.test",
        "search_query_key": "query",
        "search_index": "knowledge",
    }
    values.update(overrides)
    return KnowledgeConfig(_env_file=None, **values)


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

    def get_chunk_states_by_ids(self, ids):
        return {key: self.states[key] for key in ids if key in self.states}

    def existing_ids(self, ids):
        return set(self.get_chunk_states_by_ids(ids))

    def upsert(self, chunks):
        self.events.append("upsert")
        self.uploaded.extend(chunks)
        for chunk in chunks:
            self.states[chunk.id] = ChunkState(
                embedding_hash=chunk.embedding_hash,
                document_hash=chunk.document_hash,
                pipeline_fingerprint=chunk.pipeline_fingerprint,
            )

    def merge_metadata(self, chunks):
        self.events.append("merge")
        self.merged.extend(chunks)

    def delete(self, ids):
        self.events.append("delete")
        self.deleted.extend(ids)
        for key in ids:
            self.states.pop(key, None)

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


def test_index_checkpoint_helpers_explain_resume_and_pipeline_changes():
    checkpoint = SimpleNamespace(
        content_hash="content",
        embedded_chunks=[],
        embedded_hash=None,
        embedded_pipeline_fingerprint=None,
        indexed_hash=None,
        indexed_pipeline_fingerprint=None,
        embed_status="pending",
        index_status="pending",
        embed_attempts=0,
        index_attempts=0,
        embed_error=None,
        index_error=None,
        embed_started_at=None,
        embed_finished_at=None,
        index_started_at=None,
        index_finished_at=None,
        updated_at=datetime.now(timezone.utc),
    )
    assert embedding_needed(checkpoint, pipeline_fingerprint="v1") is True
    begin_embedding(checkpoint)
    assert checkpoint.embed_status == "running" and checkpoint.embed_attempts == 1
    chunk = EmbeddedChunk(
        id="c1",
        document_id="d1",
        text="hello",
        embedding_text="hello",
        metadata={"source": "test", "source_id": "1", "title": "T"},
        chunk_index=0,
        start_index=0,
        embedding_hash="eh",
        document_hash="dh",
        pipeline_fingerprint="v1",
        embedding=[0.0, 1.0],
    )
    assert complete_embedding(
        checkpoint, embedded_chunks=[chunk], pipeline_fingerprint="v1"
    ) is True
    assert checkpoint.embed_status == "succeeded"
    assert checkpoint.index_status == "pending"
    assert embedding_needed(checkpoint, pipeline_fingerprint="v1") is False
    assert embedding_needed(checkpoint, pipeline_fingerprint="v2") is True

    assert indexing_needed(checkpoint, pipeline_fingerprint="v1") is True
    begin_indexing(checkpoint)
    assert checkpoint.index_status == "running" and checkpoint.index_attempts == 1
    complete_indexing(checkpoint, pipeline_fingerprint="v1")
    assert indexing_needed(checkpoint, pipeline_fingerprint="v1") is False
    assert indexing_needed(checkpoint, pipeline_fingerprint="v2") is True
    fail_indexing(checkpoint, RuntimeError("write failed"))
    assert checkpoint.index_status == "failed"
    reset_indexing(checkpoint)
    assert checkpoint.index_status == "pending" and checkpoint.indexed_hash is None
    fail_embedding(checkpoint, RuntimeError("embed failed"))
    assert checkpoint.embed_status == "failed"
    reset_embedding(checkpoint)
    assert checkpoint.embed_status == "pending" and checkpoint.embedded_chunks == []


def test_prepare_embeddings_reuses_matching_sql_vectors(monkeypatch):
    chunker = _chunker()
    document = _document("Short text")
    current = chunker.split([document])[0]
    existing = EmbeddedChunk(
        **current.model_dump(),
        embedding=[9.0, 9.0],
    )
    embed_calls = []

    class TrackingEmbedder:
        def embed(self, chunks):
            embed_calls.append(len(chunks))
            return Embedder(FakeEmbeddings(), "embedding", 2).embed(chunks)

    monkeypatch.setattr(knowledge_api, "build_chunker", lambda config: chunker)
    monkeypatch.setattr(
        knowledge_api, "build_embedder", lambda config: TrackingEmbedder()
    )
    prepared = prepare_embeddings(
        [document], config=_config(), existing=[existing]
    )
    assert prepared.embedded_count == 0
    assert prepared.reused_count == 1
    assert prepared.chunks[0].embedding == [9.0, 9.0]
    assert embed_calls == []


def test_sync_embedded_chunks_skips_upsert_for_matching_azure_state(monkeypatch):
    chunker = _chunker()
    document = _document("Short text")
    current = chunker.split([document])[0]
    embedded = EmbeddedChunk(**current.model_dump(), embedding=[0.0, 1.0])
    state = ChunkState(
        embedding_hash=current.embedding_hash,
        document_hash="old-metadata-hash",
        pipeline_fingerprint=current.pipeline_fingerprint,
    )
    store = FakeStore({current.id: state, "stale": ChunkState()})
    monkeypatch.setattr(knowledge_api, "build_chunker", lambda config: chunker)
    monkeypatch.setattr(
        knowledge_api, "build_store", lambda config, *, write_enabled: store
    )
    result = sync_embedded_chunks(
        [embedded], scope={"source": "test"}, config=_config()
    )
    assert result.embedded_count == 0
    assert result.metadata_updated_count == 1
    assert result.deleted_count == 1
    assert store.events == ["merge", "delete"]


def test_sync_distinguishes_embedding_metadata_and_stale_changes_before_deletion(monkeypatch):
    chunker = _chunker()
    document = _document("Short text")
    current = chunker.split([document])[0]
    state = ChunkState(
        embedding_hash=current.embedding_hash,
        document_hash="old-metadata-hash",
        pipeline_fingerprint=current.pipeline_fingerprint,
    )
    store = FakeStore({current.id: state, "stale": ChunkState()})
    embedder = Embedder(FakeEmbeddings(), "embedding", 2)
    monkeypatch.setattr(knowledge_api, "build_chunker", lambda config: chunker)
    monkeypatch.setattr(knowledge_api, "build_embedder", lambda config: embedder)
    monkeypatch.setattr(
        knowledge_api, "build_store", lambda config, *, write_enabled: store
    )
    result = sync_documents(
        [document], scope={"source": "test"}, config=_config()
    )
    # Ad-hoc sync_documents always embeds, then Azure upsert may still skip.
    assert result.embedded_count == 1
    assert result.metadata_updated_count == 1
    assert result.deleted_count == 1
    assert store.events == ["merge", "delete"]


def test_flat_processing_embedding_and_index_functions_accept_structural_values(monkeypatch):
    chunker = _chunker()
    embeddings = FakeEmbeddings()
    embedder = Embedder(embeddings, "embedding", 2)
    store = FakeStore()

    class Index:
        def ensure(self):
            self.ensured = True

        def recreate(self):
            self.recreated = True

    index = Index()
    monkeypatch.setattr(knowledge_api, "build_chunker", lambda config: chunker)
    monkeypatch.setattr(knowledge_api, "build_embedder", lambda config: embedder)
    monkeypatch.setattr(
        knowledge_api, "build_store", lambda config, *, write_enabled: store
    )
    monkeypatch.setattr(knowledge_api, "build_index", lambda config: index)
    config = _config(search_admin_key="admin")
    source_document = _document("Structural input").model_dump(mode="json")

    chunks = chunk_documents([source_document], config=config)
    embedded = embed_chunks([chunks[0].model_dump(mode="json")], config=config)
    result = index_chunks([embedded[0].model_dump(mode="json")], config=config)
    ensure_index(config=config)
    recreate_index(config=config)

    assert result.chunk_ids == [chunks[0].id]
    assert store.uploaded[0].embedding == [0.0, 1.0]
    assert index.ensured is index.recreated is True
    assert embed_query("query", config=config) == [9.0, 1.0]
    assert pipeline_fingerprint(config=config) == chunker.pipeline_fingerprint


def test_settings_validate_cross_field_constraints_and_tokenizer_load_errors(monkeypatch):
    for key in (
        "AZURE_SEARCH_ADMIN_KEY",
        "AZURE_SEARCH_API_KEY",
        "AZURE_SEARCH_QUERY_KEY",
    ):
        monkeypatch.delenv(key, raising=False)
    values = dict(
        openai_endpoint="https://openai.test", openai_api_key="secret",
        embedding_deployment="embedding", search_endpoint="https://search.test",
        search_query_key="query", search_index="knowledge",
    )
    config = KnowledgeConfig(_env_file=None, **values)
    assert config.search_admin_key is None
    with pytest.raises(Exception, match="RAG_CHUNK_OVERLAP"):
        KnowledgeConfig(_env_file=None, **values, chunk_size=10, chunk_overlap=10)
    with pytest.raises(TokenizerError, match="Unable to load"):
        load_encoding("not-a-real-tiktoken-encoding")


def test_retrieval_modes_and_evidence_policy_deduplicate_and_cap_documents(monkeypatch):
    chunks = [
        RetrievedChunk(id="1", document_id="a", text="same", metadata={"source": "x", "source_id": "1", "title": "T"}, score=4),
        RetrievedChunk(id="2", document_id="b", text="same", metadata={"source": "x", "source_id": "2", "title": "T"}, score=3),
        RetrievedChunk(id="3", document_id="a", text="other", metadata={"source": "x", "source_id": "1", "title": "T"}, score=2),
        RetrievedChunk(id="4", document_id="a", text="third", metadata={"source": "x", "source_id": "1", "title": "T"}, score=1),
    ]
    store = FakeStore(results=chunks)
    monkeypatch.setattr(
        knowledge_api, "build_store", lambda config, *, write_enabled: store
    )
    monkeypatch.setattr(
        knowledge_api, "pipeline_fingerprint", lambda *, config: "fingerprint"
    )
    result = retrieve_chunks(
        "query", query_embedding=[9.0, 1.0],
        mode=RetrievalMode.SEMANTIC_HYBRID,
        candidate_k=50, fetch_k=24, top_k=3,
        include_diagnostics=True, config=_config(),
    )
    assert [chunk.id for chunk in result.chunks] == ["1", "3"]
    assert result.rejection_counts.duplicate_content == 1
    assert result.rejection_counts.per_document_cap == 1
    assert store.query_vector == [9.0, 1.0]

    chunks_only = retrieve_chunks(
        "query", query_embedding=[9.0, 1.0], top_k=3, config=_config()
    )
    assert [chunk.id for chunk in chunks_only] == ["1", "3"]


def test_optional_reranker_threshold_can_produce_insufficient_evidence(monkeypatch):
    store = FakeStore(results=[RetrievedChunk(
        id="1", document_id="a", text="evidence",
        metadata={"source": "x", "source_id": "1", "title": "T"},
        score=1, reranker_score=1.5,
    )])
    monkeypatch.setattr(
        knowledge_api, "build_store", lambda config, *, write_enabled: store
    )
    with pytest.raises(InsufficientEvidenceError):
        retrieve_chunks(
            "query", query_embedding=[9.0, 1.0], candidate_k=50,
            fetch_k=8, top_k=8,
            evidence_policy=EvidencePolicy(minimum_reranker_score=2),
            config=_config(),
        )


def test_filter_builder_escapes_strings_and_rejects_unknown_fields():
    assert build_filter({"source": "author's"}) == "source eq 'author''s'"
    with pytest.raises(ValueError, match="not filterable"):
        build_filter({"metadata_json": "unsafe"})


def test_azure_store_batches_by_count_and_retries_transient_partial_failures():
    class Client:
        def __init__(self):
            self.calls = []

        def merge_or_upload_documents(self, *, documents):
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
