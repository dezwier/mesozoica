"""Structured generation over retrieved evidence."""

from mesozoica_ai.generate.prompt import prompt_rag
from mesozoica_ai.generate.quiz import (
    QuizQuestion,
    QuizUserContext,
    answer_from_index,
    generate_quiz,
    print_model,
    require_one_subject,
)

__all__ = [
    "QuizQuestion",
    "QuizUserContext",
    "answer_from_index",
    "generate_quiz",
    "print_model",
    "prompt_rag",
    "require_one_subject",
]
