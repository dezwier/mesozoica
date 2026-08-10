"""Exact token counting for prompt assembly."""

from functools import lru_cache
from typing import Protocol

from .errors import RagConfigurationError


class Encoding(Protocol):
    """Tokenizer behavior used by production and tests."""

    def encode(self, text: str, *, disallowed_special: tuple = ()) -> list[int]: ...

    def decode(self, tokens: list[int]) -> str: ...


@lru_cache(maxsize=4)
def load_encoding(name: str) -> Encoding:
    """Load and cache one tiktoken encoding."""
    try:
        import tiktoken

        return tiktoken.get_encoding(name)
    except Exception as exc:
        raise RagConfigurationError(f"Unable to load tiktoken encoding {name!r}") from exc


class TokenCounter:
    """Count and truncate text with the configured tokenizer."""

    def __init__(self, encoding_name: str, *, encoding: Encoding | None = None) -> None:
        self.encoding = encoding or load_encoding(encoding_name)

    def count(self, text: str) -> int:
        """Return the exact token count."""
        return len(self.encoding.encode(text, disallowed_special=()))

    def truncate(self, text: str, limit: int) -> str:
        """Return no more than ``limit`` tokens."""
        if limit <= 0:
            return ""
        tokens = self.encoding.encode(text, disallowed_special=())
        return text if len(tokens) <= limit else self.encoding.decode(tokens[:limit])
