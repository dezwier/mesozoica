from types import SimpleNamespace

import pytest
from langchain_core.runnables import RunnableLambda
from pydantic import BaseModel

from mesozoica_ai.evaluation import (
    FoundryRagEvaluator,
    RagEvaluationRecord,
    RetrievalCase,
    evaluate_retrieval,
)
from mesozoica_ai.generation import StructuredRag, pack_context, validate_citations
from mesozoica_ai.knowledge import RetrievedChunk


def _chunk(identifier, document_id, text="Evidence"):
    return RetrievedChunk(
        id=identifier,
        document_id=document_id,
        text=text,
        metadata={"source": "test", "source_url": "https://example.test"},
        score=1.0,
    )


def test_context_budget_and_citation_validation():
    chunks = [_chunk("one", "doc-1", "word " * 100), _chunk("two", "doc-2")]
    context = pack_context(chunks, token_budget=60)
    assert "one" in context
    assert "two" not in context
    validate_citations(["one"], chunks)
    with pytest.raises(ValueError, match="unknown chunks"):
        validate_citations(["missing"], chunks)


def test_retrieval_metrics_are_exact():
    chunks = [_chunk("1", "a"), _chunk("2", "x"), _chunk("3", "b")]
    report = evaluate_retrieval(
        [
            RetrievalCase(
                id="case", query="query", relevant_document_ids={"a": 2, "b": 1}, top_k=3
            )
        ],
        lambda request: chunks,
    )
    assert report.precision_at_k == pytest.approx(2 / 3)
    assert report.recall_at_k == 1
    assert report.hit_rate_at_k == 1
    assert report.mrr == 1
    assert report.ndcg_at_k == pytest.approx(3.5 / (3 + 1 / 1.584962500721156))


class Quiz(BaseModel):
    question: str


class FakeKnowledge:
    def retrieve(self, request):
        return [_chunk("one", "doc-1")]


class FakeChat:
    def with_structured_output(self, output_model, **kwargs):
        return RunnableLambda(
            lambda prompt: {
                "parsed": output_model(question="Question?"),
                "raw": SimpleNamespace(usage_metadata={"input_tokens": 10}),
                "parsing_error": None,
            }
        )


def test_structured_rag_returns_validated_output_and_evidence():
    result = StructuredRag(
        knowledge_base=FakeKnowledge(), llm=FakeChat(), context_token_budget=100
    ).generate(Quiz, query="Make a question", application_context={"difficulty": "easy"})
    assert result.output.question == "Question?"
    assert result.chunks[0].id == "one"
    assert result.usage == {"input_tokens": 10}


class FakeRuns:
    def create(self, **kwargs):
        self.create_kwargs = kwargs
        return SimpleNamespace(id="run-1", status="completed", report_url="https://report")


class FakeEvals:
    def __init__(self):
        self.runs = FakeRuns()

    def create(self, **kwargs):
        self.create_kwargs = kwargs
        return SimpleNamespace(id="eval-1")


def test_foundry_adapter_maps_rag_evaluators_without_live_calls():
    evals = FakeEvals()
    openai = SimpleNamespace(evals=evals)
    project = SimpleNamespace(get_openai_client=lambda: openai)
    evaluator = FoundryRagEvaluator(
        project_endpoint="https://project", judge_model="judge", project_client_factory=lambda: project
    )
    result = evaluator.submit(
        [
            RagEvaluationRecord(
                query="q",
                response="a",
                context="c",
                ground_truth="a",
                retrieval_ground_truth=[{"document_id": "1", "query_relevance_label": 4}],
                retrieved_documents=[{"document_id": "1", "relevance_score": 1.0}],
            )
        ],
        name="test",
    )
    names = [criterion["name"] for criterion in evals.create_kwargs["testing_criteria"]]
    assert names == [
        "groundedness",
        "relevance",
        "response_completeness",
        "document_retrieval",
    ]
    assert result.report_url == "https://report"
