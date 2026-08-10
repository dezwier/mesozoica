"""Optional typed adapter for Microsoft Foundry cloud RAG evaluations."""

from __future__ import annotations

import time
from collections.abc import Callable
from contextlib import ExitStack, contextmanager
from typing import Any

from pydantic import BaseModel, Field


class RagEvaluationRecord(BaseModel):
    """One cloud evaluation item and optional ground truths."""

    query: str
    response: str
    context: str
    ground_truth: str | None = None
    retrieval_ground_truth: list[dict[str, Any]] = Field(default_factory=list)
    retrieved_documents: list[dict[str, Any]] = Field(default_factory=list)


class FoundryEvaluationResult(BaseModel):
    """Terminal or bounded-wait Foundry run state and inspectable output items."""

    evaluation_id: str
    run_id: str
    status: str
    report_url: str | None = None
    output_items: list[dict[str, Any]] = Field(default_factory=list)
    timed_out: bool = False


class FoundryRagEvaluator:
    """Submit current built-in RAG evaluators through an Azure AI Projects client."""

    TERMINAL = frozenset({"completed", "failed", "cancelled"})

    def __init__(
        self, *, project_endpoint: str, deployment_name: str,
        project_client_factory: Callable[[], Any] | None = None,
        sleeper: Callable[[float], None] = time.sleep,
        monotonic: Callable[[], float] = time.monotonic,
    ) -> None:
        self.project_endpoint = project_endpoint
        self.deployment_name = deployment_name
        self.project_client_factory = project_client_factory
        self.sleeper = sleeper
        self.monotonic = monotonic

    def submit(
        self, records: list[RagEvaluationRecord], *, name: str, wait: bool = True,
        max_wait_seconds: int = 600, include_response_completeness: bool = True,
    ) -> FoundryEvaluationResult:
        """Create an evaluation/run, poll within bounds, and retrieve output items."""
        if not records:
            raise ValueError("At least one evaluation record is required")
        with ExitStack() as stack:
            project = stack.enter_context(self._project_context())
            openai = project.get_openai_client()
            if hasattr(openai, "__enter__"):
                openai = stack.enter_context(openai)
            evaluation = openai.evals.create(
                name=name,
                data_source_config=self._data_source_config(),
                testing_criteria=self._criteria(records, include_response_completeness),
            )
            run = openai.evals.runs.create(
                eval_id=evaluation.id,
                name=f"{name}-run",
                data_source={
                    "type": "jsonl",
                    "source": {"type": "file_content", "content": [
                        {"item": record.model_dump(mode="json")} for record in records
                    ]},
                },
            )
            timed_out = False
            if wait:
                deadline = self.monotonic() + max_wait_seconds
                while run.status not in self.TERMINAL:
                    if self.monotonic() >= deadline:
                        timed_out = True
                        break
                    self.sleeper(min(5, max_wait_seconds))
                    run = openai.evals.runs.retrieve(eval_id=evaluation.id, run_id=run.id)
            output_items: list[dict[str, Any]] = []
            if run.status == "completed":
                listed = openai.evals.runs.output_items.list(
                    eval_id=evaluation.id, run_id=run.id
                )
                output_items = [
                    item.model_dump(mode="json") if hasattr(item, "model_dump") else dict(item)
                    for item in listed
                ]
            return FoundryEvaluationResult(
                evaluation_id=evaluation.id,
                run_id=run.id,
                status=run.status,
                report_url=getattr(run, "report_url", None),
                output_items=output_items,
                timed_out=timed_out,
            )

    @contextmanager
    def _project_context(self):
        if self.project_client_factory:
            project = self.project_client_factory()
            if hasattr(project, "__enter__"):
                with project as entered:
                    yield entered
            else:
                yield project
            return
        try:
            from azure.ai.projects import AIProjectClient
            from azure.identity import DefaultAzureCredential
        except ImportError as exc:  # pragma: no cover
            raise RuntimeError("Install mesozoica-ai[foundry] for Foundry evaluation") from exc
        with DefaultAzureCredential() as credential, AIProjectClient(
            endpoint=self.project_endpoint, credential=credential
        ) as project:
            yield project

    @staticmethod
    def _data_source_config() -> Any:
        schema = {
            "type": "object",
            "properties": {
                "query": {"type": "string"}, "response": {"type": "string"},
                "context": {"type": "string"},
                "ground_truth": {"type": ["string", "null"]},
                "retrieval_ground_truth": {"type": "array"},
                "retrieved_documents": {"type": "array"},
            },
            "required": ["query", "response", "context"],
        }
        try:
            from openai.types.eval_create_params import DataSourceConfigCustom

            return DataSourceConfigCustom(type="custom", item_schema=schema,
                                          include_sample_schema=True)
        except ImportError:  # exercised by offline injected-client tests
            return {"type": "custom", "item_schema": schema, "include_sample_schema": True}

    def _criteria(self, records: list[RagEvaluationRecord], completeness: bool) -> list[Any]:
        criteria = [
            self._criterion("groundedness", {"query": "{{item.query}}", "response": "{{item.response}}", "context": "{{item.context}}"}),
            self._criterion("relevance", {"query": "{{item.query}}", "response": "{{item.response}}"}),
            self._criterion("retrieval", {"query": "{{item.query}}", "context": "{{item.context}}"}),
        ]
        if completeness and any(record.ground_truth for record in records):
            criteria.append(self._criterion("response_completeness", {
                "ground_truth": "{{item.ground_truth}}", "response": "{{item.response}}",
            }))
        if any(record.retrieval_ground_truth for record in records):
            criteria.append(self._criterion("document_retrieval", {
                "retrieval_ground_truth": "{{item.retrieval_ground_truth}}",
                "retrieved_documents": "{{item.retrieved_documents}}",
            }, deployment=False))
        return criteria

    def _criterion(self, evaluator: str, mapping: dict[str, str], *, deployment: bool = True) -> Any:
        values: dict[str, Any] = {
            "type": "azure_ai_evaluator", "name": evaluator,
            "evaluator_name": f"builtin.{evaluator}", "data_mapping": mapping,
        }
        if deployment:
            values["initialization_parameters"] = {"deployment_name": self.deployment_name}
        try:
            from azure.ai.projects.models import TestingCriterionAzureAIEvaluator

            return TestingCriterionAzureAIEvaluator(**values)
        except ImportError:
            return values
