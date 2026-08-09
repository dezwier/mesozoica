from __future__ import annotations

import time
from collections.abc import Callable
from typing import Any

from pydantic import BaseModel, Field


class RagEvaluationRecord(BaseModel):
    query: str
    response: str
    context: str
    ground_truth: str | None = None
    retrieval_ground_truth: list[dict[str, Any]] = Field(default_factory=list)
    retrieved_documents: list[dict[str, Any]] = Field(default_factory=list)


class FoundryEvaluationResult(BaseModel):
    evaluation_id: str
    run_id: str
    status: str
    report_url: str | None = None


class FoundryRagEvaluator:
    """Thin optional adapter over Microsoft Foundry cloud evaluations."""

    def __init__(
        self,
        *,
        project_endpoint: str,
        judge_model: str,
        project_client_factory: Callable[[], Any] | None = None,
        sleeper: Callable[[float], None] = time.sleep,
    ) -> None:
        self.project_endpoint = project_endpoint
        self.judge_model = judge_model
        self.project_client_factory = project_client_factory
        self.sleeper = sleeper

    def submit(
        self,
        records: list[RagEvaluationRecord],
        *,
        name: str,
        wait: bool = True,
        max_wait_seconds: int = 600,
    ) -> FoundryEvaluationResult:
        if not records:
            raise ValueError("At least one evaluation record is required")
        project_client = self._project_client()
        openai_client = project_client.get_openai_client()
        schema = {
            "type": "object",
            "properties": {
                "query": {"type": "string"},
                "response": {"type": "string"},
                "context": {"type": "string"},
                "ground_truth": {"type": ["string", "null"]},
                "retrieval_ground_truth": {"type": "array"},
                "retrieved_documents": {"type": "array"},
            },
            "required": ["query", "response", "context"],
        }
        criteria = [
            self._criterion("groundedness", {"query": "{{item.query}}", "response": "{{item.response}}", "context": "{{item.context}}"}),
            self._criterion("relevance", {"query": "{{item.query}}", "response": "{{item.response}}"}),
        ]
        if any(record.ground_truth for record in records):
            criteria.append(
                self._criterion(
                    "response_completeness",
                    {"ground_truth": "{{item.ground_truth}}", "response": "{{item.response}}"},
                )
            )
        if any(record.retrieval_ground_truth for record in records):
            criteria.append(
                self._criterion(
                    "document_retrieval",
                    {
                        "retrieval_ground_truth": "{{item.retrieval_ground_truth}}",
                        "retrieved_documents": "{{item.retrieved_documents}}",
                    },
                    model=False,
                )
            )
        evaluation = openai_client.evals.create(
            name=name,
            data_source_config={
                "type": "custom",
                "item_schema": schema,
                "include_sample_schema": True,
            },
            testing_criteria=criteria,
        )
        run = openai_client.evals.runs.create(
            eval_id=evaluation.id,
            name=f"{name}-run",
            data_source={
                "type": "jsonl",
                "source": {
                    "type": "file_content",
                    "content": [{"item": record.model_dump(mode="json")} for record in records],
                },
            },
        )
        if wait:
            deadline = time.monotonic() + max_wait_seconds
            while run.status not in {"completed", "failed", "cancelled"}:
                if time.monotonic() >= deadline:
                    break
                self.sleeper(5)
                run = openai_client.evals.runs.retrieve(
                    eval_id=evaluation.id, run_id=run.id
                )
        return FoundryEvaluationResult(
            evaluation_id=evaluation.id,
            run_id=run.id,
            status=run.status,
            report_url=getattr(run, "report_url", None),
        )

    def _project_client(self):
        if self.project_client_factory:
            return self.project_client_factory()
        try:
            from azure.ai.projects import AIProjectClient
            from azure.identity import DefaultAzureCredential
        except ImportError as exc:  # pragma: no cover - environment dependent
            raise RuntimeError(
                "Install mesozoica-ai[foundry] to submit Foundry evaluations"
            ) from exc
        return AIProjectClient(
            endpoint=self.project_endpoint, credential=DefaultAzureCredential()
        )

    def _criterion(self, evaluator: str, mapping: dict[str, str], *, model: bool = True) -> dict:
        criterion = {
            "type": "azure_ai_evaluator",
            "name": evaluator,
            "evaluator_name": f"builtin.{evaluator}",
            "data_mapping": mapping,
        }
        if model:
            criterion["initialization_parameters"] = {"model": self.judge_model}
        return criterion
