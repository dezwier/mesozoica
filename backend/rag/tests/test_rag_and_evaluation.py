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
from mesozoica_ai.generate.prompt import _coerce_citations, _pack_evidence, _validate_citations
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


def test_coerce_citations_drops_unknown_ids_when_valid_remain():
    class Answer(CitedOutput):
        answer: str

    parsed = Answer(answer="ok", source_chunk_ids=["one", "missing"])
    coerced = _coerce_citations(parsed, ["one", "two"])
    assert coerced.source_chunk_ids == ["one"]
    replaced = _coerce_citations(
        Answer(answer="bad", source_chunk_ids=["missing"]),
        ["one", "two"],
    )
    assert replaced.source_chunk_ids == ["one", "two"]
    with pytest.raises(CitationError, match="at least one"):
        _coerce_citations(Answer(answer="empty", source_chunk_ids=["missing"]), [])


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


def test_prompt_rag_drops_unknown_citations(monkeypatch):
    chat = FakeChat(Quiz(question="Question?", source_chunk_ids=["one", "hallucinated"]))
    monkeypatch.setattr(rag_prompt, "ChatOpenAI", lambda **kwargs: chat)
    monkeypatch.setattr(rag_prompt, "TokenCounter", lambda encoding: COUNTER)
    result = prompt_rag(
        Quiz,
        query="Make a question",
        evidence=[_chunk("one", "doc-1")],
        config=_rag_config(),
    )
    assert result.source_chunk_ids == ["one"]


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


def test_require_one_subject_and_quiz_question_validation():
    from types import SimpleNamespace

    from mesozoica_ai.generate import QuizQuestion, require_one_subject

    subject = SimpleNamespace(id=12, name="Abrosaurus")
    assert require_one_subject([subject], requested="Abrosaurus") is subject
    with pytest.raises(ValueError, match="exactly one"):
        require_one_subject([], requested="Abrosaurus")
    with pytest.raises(ValueError, match="exactly one"):
        require_one_subject([subject, subject], requested="Abrosaurus")

    quiz = QuizQuestion(
        question="Which clade includes Abrosaurus?",
        topic="classification",
        difficulty="medium",
        options=("Sauropoda", "Theropoda", "Ornithopoda", "Ceratopsia"),
        correct_index=0,
        explanation="Abrosaurus is a sauropod.",
        source_chunk_ids=["chunk-1"],
    )
    assert quiz.correct_index == 0
    with pytest.raises(ValueError, match="unique"):
        QuizQuestion(
            question="Q?",
            topic="t",
            difficulty="easy",
            options=("A", "A", "B", "C"),
            correct_index=0,
            explanation="because",
            source_chunk_ids=["chunk-1"],
        )


def test_generate_quiz_wires_retrieve_filters_and_user_context(monkeypatch):
    from types import SimpleNamespace

    from mesozoica_ai.generate import QuizQuestion, QuizUserContext, generate_quiz
    from mesozoica_ai.generate import answer as answer_mod

    captured: dict = {}

    def fake_answer_from_index(output_model, *, query, filters, config, application_context, instructions, mode=None):
        captured.update(
            {
                "output_model": output_model,
                "query": query,
                "filters": filters,
                "application_context": application_context,
                "instructions": instructions,
                "mode": mode,
            }
        )
        return QuizQuestion(
            question="Q?",
            topic="anatomy",
            difficulty="hard",
            options=("a", "b", "c", "d"),
            correct_index=1,
            explanation="from evidence",
            source_chunk_ids=["ev-1"],
        )

    monkeypatch.setattr(answer_mod, "answer_from_index", fake_answer_from_index)
    monkeypatch.setattr(
        "mesozoica_ai.generate.quiz.answer_from_index", fake_answer_from_index
    )
    context = QuizUserContext(
        language="English",
        knowledge_level="beginner",
        preferred_difficulty="hard",
    )
    result = generate_quiz(
        subject=SimpleNamespace(id=12, name="Abrosaurus"),
        user_context=context,
        config=_rag_config(),
    )
    assert result.topic == "anatomy"
    assert captured["output_model"] is QuizQuestion
    assert captured["filters"] == {
        "namespace": "mesozoica",
        "subject_id": "dinosaur:12",
    }
    assert captured["application_context"] is context
    assert "Abrosaurus" in captured["query"]
    assert "hard" in captured["query"]


def test_retrieved_chunk_record_exposes_ranking_and_provenance():
    from mesozoica_ai.common.models import RetrievedChunk, SourceMetadata
    from mesozoica_ai.generate import quiz_retrieval_plan, retrieved_chunk_record

    query, filters, instructions = quiz_retrieval_plan(
        subject_id=12,
        subject_name="Abrosaurus",
    )
    assert filters == {"namespace": "mesozoica", "subject_id": "dinosaur:12"}
    assert "Abrosaurus" in query and "Abrosaurus" in instructions

    record = retrieved_chunk_record(
        RetrievedChunk(
            id="chunk-1",
            document_id="doc-1",
            text="Abrosaurus was a sauropod.",
            metadata=SourceMetadata(
                source="openalex",
                source_id="W123",
                title="Paper title",
                section="Abstract",
                section_path=["Abstract"],
                source_url="https://example.test/paper",
                namespace="mesozoica",
                subject_id="dinosaur:12",
                subject_name="Abrosaurus",
            ),
            chunk_index=0,
            score=12.5,
            reranker_score=2.1,
        )
    )
    assert record == {
        "id": "chunk-1",
        "document_id": "doc-1",
        "chunk_index": 0,
        "score": 12.5,
        "reranker_score": 2.1,
        "source": "openalex",
        "source_id": "W123",
        "title": "Paper title",
        "section": "Abstract",
        "section_path": ["Abstract"],
        "source_url": "https://example.test/paper",
        "namespace": "mesozoica",
        "subject_id": "dinosaur:12",
        "subject_name": "Abrosaurus",
        "published_at": None,
        "text": "Abrosaurus was a sauropod.",
    }


def test_format_chunk_log_lines_are_compact():
    from mesozoica_ai.generate.quiz import format_chunk_log_lines

    lines = format_chunk_log_lines(
        [
            {
                "id": "abcdef0123456789",
                "score": 0.03079839,
                "reranker_score": None,
                "source": "wikipedia",
                "title": "Achelousaurus",
                "section": "Skull",
                "text": "The skull of Achelousaurus was heavily ornamented with bosses.",
            }
        ],
        preview_chars=40,
    )
    assert lines[0] == "retrieved 1 chunk(s)"
    assert lines[1] == "  [1] 0.031 wikipedia | Achelousaurus · Skull | abcdef0123"
    assert lines[2] == "       The skull of Achelousaurus was heavily…"


def test_answer_question_uses_evidence_only_without_application_context(monkeypatch):
    from mesozoica_ai.generate import GroundedAnswer, answer_question
    from mesozoica_ai.generate import answer as answer_mod

    captured: dict = {}

    def fake_answer_from_index(output_model, *, query, filters, config, application_context, instructions, mode=None):
        captured.update(
            {
                "output_model": output_model,
                "query": query,
                "filters": filters,
                "application_context": application_context,
                "instructions": instructions,
                "mode": mode,
            }
        )
        return GroundedAnswer(
            answer="Abrosaurus was a sauropod.",
            source_chunk_ids=["ev-1"],
        )

    monkeypatch.setattr(answer_mod, "answer_from_index", fake_answer_from_index)
    result = answer_question(
        query="What was Abrosaurus?",
        subject_id=12,
        config=_rag_config(),
        mode="hybrid",
    )
    assert result.answer.startswith("Abrosaurus")
    assert captured["output_model"] is GroundedAnswer
    assert captured["application_context"] is None
    assert captured["filters"] == {
        "namespace": "mesozoica",
        "subject_id": "dinosaur:12",
    }
    assert captured["mode"] == "hybrid"
    assert "only the supplied evidence" in captured["instructions"]
