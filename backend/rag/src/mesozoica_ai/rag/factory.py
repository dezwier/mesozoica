"""Azure OpenAI construction for the structured RAG generator."""

from langchain_openai import ChatOpenAI

from .settings import RagSettings
from .generator import Rag
from .tokens import TokenCounter


def create_rag(settings: RagSettings) -> Rag:
    """Create a strict generator; retrieval remains the caller's responsibility."""
    llm = ChatOpenAI(
        model=settings.chat_deployment,
        base_url=settings.openai_v1_base_url,
        api_key=settings.openai_api_key.get_secret_value(),
        temperature=0,
        max_tokens=settings.max_completion_tokens,
    )
    return Rag(
        llm=llm,
        token_counter=TokenCounter(settings.chat_encoding),
        max_prompt_tokens=settings.max_prompt_tokens,
        max_completion_tokens=settings.max_completion_tokens,
        safety_margin=settings.prompt_safety_margin,
    )
