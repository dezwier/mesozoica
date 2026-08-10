"""Exact tokenizer helpers used by document chunking."""

from __future__ import annotations

from functools import lru_cache
from typing import Protocol

from .errors import KnowledgeBaseConfigurationError


class Encoding(Protocol):
    """Small protocol implemented by tiktoken encodings and test doubles."""

    name: str

    def encode(self, text: str, *, disallowed_special: tuple = ()) -> list[int]:
        """Encode text to integer token IDs."""
        ...

    def decode(self, tokens: list[int]) -> str:
        """Decode integer token IDs to text."""
        ...


@lru_cache(maxsize=8)
def load_encoding(name: str) -> Encoding:
    """Load and cache a named tiktoken encoding, failing with actionable context."""
    try:
        import tiktoken

        return tiktoken.get_encoding(name)
    except Exception as exc:
        raise KnowledgeBaseConfigurationError(
            f"Unable to load tiktoken encoding {name!r}. Install/cache tokenizer assets "
            "during the image build and verify RAG_*_ENCODING."
        ) from exc


class TokenCounter:
    """Count and truncate text using one exact tokenizer encoding."""

    def __init__(self, encoding_name: str, *, encoding: Encoding | None = None) -> None:
        self.encoding_name = encoding_name
        self.encoding = encoding or load_encoding(encoding_name)

    def count(self, text: str) -> int:
        """Return the exact number of model tokens in text."""
        return len(self.encoding.encode(text, disallowed_special=()))

    def truncate(self, text: str, limit: int) -> str:
        """Return at most ``limit`` exact tokens without character approximation."""
        if limit <= 0:
            return ""
        tokens = self.encoding.encode(text, disallowed_special=())
        return text if len(tokens) <= limit else self.encoding.decode(tokens[:limit])
