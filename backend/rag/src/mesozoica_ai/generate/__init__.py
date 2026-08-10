"""Structured generation over retrieved evidence."""

from mesozoica_ai.generate.answer import (
    GroundedAnswer,
    answer_from_index,
    answer_question,
)
from mesozoica_ai.generate.prompt import prompt_rag
from mesozoica_ai.generate.quiz import (
    QuizQuestion,
    QuizUserContext,
    generate_quiz,
    log_retrieved_chunks,
    print_model,
    quiz_retrieval_plan,
    require_one_subject,
    retrieved_chunk_record,
)

__all__ = [
    "GroundedAnswer",
    "QuizQuestion",
    "QuizUserContext",
    "answer_from_index",
    "answer_question",
    "generate_quiz",
    "log_retrieved_chunks",
    "print_model",
    "prompt_rag",
    "quiz_retrieval_plan",
    "require_one_subject",
    "retrieved_chunk_record",
]
