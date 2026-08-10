from types import SimpleNamespace

import pytest
from langchain_core.runnables import RunnableLambda
from pydantic import BaseModel

from mesozoica_ai.common.config import AiConfig as RagConfig
from mesozoica_ai.common.errors import CitationError
from mesozoica_ai.generate import prompt_rag
from mesozoica_ai.generate import prompt as rag_prompt
from mesozoica_ai.evaluate import (
    RetrievalCase,
    compare_to_baseline,
    evaluate_retrieval,
)
from mesozoica_ai.evaluate.foundry import FoundryRagEvaluator, RagEvaluationRecord
from mesozoica_ai.common.models import CitedOutput, Evidence
from mesozoica_ai.generate.prompt import _pack_evidence, _validate_citations
from mesozoica_ai.common.tokens import TokenCounter


class CharacterEncoding:
    name = "characters"
    def encode(self, text, *, disallowed_special=()): return [ord(x) for x in text]
    def decode(self, tokens): return "".join(chr(x) for x in tokens)


COUNTER = TokenCounter("characters", encoding=CharacterEncoding())


def _chunk(identifier, document_id, text="Evidence"):
    return Evidence(
        id=identifier,
        document_id=document_id,
        text=text,
        source="test",
        url="https://example.test",
    )


def test_prompt_budget_and_explicit_citation_validation():
    evidence, included, omitted = _pack_evidence(
        [_chunk("one", "doc-1", "word " * 100), _chunk("two", "doc-2")],
        token_budget=180, token_counter=COUNTER,
    )
    assert "one" in evidence and included == ["one"] and omitted == ["two"]
    _validate_citations(["one"], ["one"])
    with pytest.raises(CitationError, match="unknown evidence"):
        _validate_citations(["missing"], ["one"])


def test_retrieval_metrics_and_baseline_regression_are_exact():
    report = evaluate_retrieval(
        [RetrievalCase(id="case", query="query", relevant_document_ids={"a": 2, "b": 1}, top_k=3)],
        lambda case, run: ["a", "x", "b"],
        pipeline_fingerprint="fp", top_k=3,
    )
    assert report.precision_at_k == pytest.approx(2 / 3)
    assert report.recall_at_k == report.hit_rate_at_k == report.mrr == 1
    worse = report.model_copy(update={"mrr": 0.97})
    assert compare_to_baseline(worse, report).passed is False


class Quiz(CitedOutput):
    question: str


class UncitedQuiz(BaseModel):
    question: str
    source_chunk_ids: list[str]


class FakeChat:
    def __init__(self, output): self.output = output; self.kwargs = None
    def with_structured_output(self, output_model, **kwargs):
        self.kwargs = kwargs
        return RunnableLambda(lambda prompt: {
            "parsed": self.output, "raw": SimpleNamespace(usage_metadata={"input_tokens": 10}),
            "parsing_error": None,
        })


def _rag_config():
    return RagConfig(
        _env_file=None,
        openai_endpoint="https://openai.test",
        openai_api_key="secret",
        embedding_deployment="embedding",
        search_endpoint="https://search.test",
        search_query_key="query",
        search_index="knowledge",
        chat_deployment="chat",
        max_prompt_tokens=3000,
        max_completion_tokens=100,
        prompt_safety_margin=50,
    )


def test_prompt_rag_uses_strict_schema_and_returns_model_directly(monkeypatch):
    chat = FakeChat(Quiz(question="Question?", source_chunk_ids=["one"]))
    monkeypatch.setattr(rag_prompt, "ChatOpenAI", lambda **kwargs: chat)
    monkeypatch.setattr(rag_prompt, "TokenCounter", lambda encoding: COUNTER)
    result = prompt_rag(
        Quiz,
        query="Make a question",
        evidence=[_chunk("one", "doc-1")],
        trace_config={"tags": ["test"]},
        config=_rag_config(),
    )
    assert result.question == "Question?"
    assert chat.kwargs["strict"] is True


def test_magic_citation_field_is_not_validated_without_explicit_base_model(monkeypatch):
    output = UncitedQuiz(question="Question?", source_chunk_ids=["not-real"])
    monkeypatch.setattr(rag_prompt, "ChatOpenAI", lambda **kwargs: FakeChat(output))
    monkeypatch.setattr(rag_prompt, "TokenCounter", lambda encoding: COUNTER)
    result = prompt_rag(
        UncitedQuiz, query="Question", evidence=[_chunk("one", "doc-1")],
        config=_rag_config(),
    )
    assert result.source_chunk_ids == ["not-real"]


class FakeOutputItems:
    def list(self, **kwargs): return [{"id": "item-1"}]


class FakeRuns:
    def __init__(self): self.output_items = FakeOutputItems()
    def create(self, **kwargs): return SimpleNamespace(id="run-1", status="completed", report_url="https://report")


class FakeEvals:
    def __init__(self): self.runs = FakeRuns()
    def create(self, **kwargs): self.create_kwargs = kwargs; return SimpleNamespace(id="eval-1")


def test_foundry_adapter_maps_current_rag_evaluators_without_live_calls():
    evals = FakeEvals()
    project = SimpleNamespace(get_openai_client=lambda: SimpleNamespace(evals=evals))
    result = FoundryRagEvaluator(
        project_endpoint="https://project", deployment_name="judge",
        project_client_factory=lambda: project,
    ).submit([RagEvaluationRecord(
        query="q", response="a", context="c", ground_truth="a",
        retrieval_ground_truth=[{"document_id": "1", "query_relevance_label": 4}],
        retrieved_documents=[{"document_id": "1", "relevance_score": 1}],
    )], name="test")
    names = [criterion["name"] for criterion in evals.create_kwargs["testing_criteria"]]
    assert names == ["groundedness", "relevance", "retrieval", "response_completeness", "document_retrieval"]
    assert evals.create_kwargs["testing_criteria"][0]["initialization_parameters"] == {"deployment_name": "judge"}
    assert result.report_url == "https://report" and result.output_items == [{"id": "item-1"}]


def test_foundry_polling_reports_timeout_without_requesting_output_items():
    class Runs:
        output_items = SimpleNamespace(list=lambda **kwargs: (_ for _ in ()).throw(AssertionError()))
        def create(self, **kwargs): return SimpleNamespace(id="run", status="queued", report_url=None)
        def retrieve(self, **kwargs): return SimpleNamespace(id="run", status="queued", report_url=None)

    evals = SimpleNamespace(
        runs=Runs(),
        create=lambda **kwargs: SimpleNamespace(id="eval"),
    )
    project = SimpleNamespace(get_openai_client=lambda: SimpleNamespace(evals=evals))
    times = iter([0, 2])
    result = FoundryRagEvaluator(
        project_endpoint="https://project", deployment_name="judge",
        project_client_factory=lambda: project, sleeper=lambda _: None,
        monotonic=lambda: next(times),
    ).submit([RagEvaluationRecord(query="q", response="a", context="c")],
             name="timeout", max_wait_seconds=1)
    assert result.status == "queued" and result.timed_out is True
