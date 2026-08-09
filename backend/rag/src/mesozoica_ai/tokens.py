from __future__ import annotations

import re

_TOKEN = re.compile(r"\w+|[^\w\s]", re.UNICODE)


def count_tokens(text: str, *, encoding_name: str = "unicode-word-v1") -> int:
    """Deterministic offline token approximation suitable for chunk budgets."""
    if encoding_name != "unicode-word-v1":
        raise ValueError(f"Unsupported offline token encoding: {encoding_name}")
    return len(_TOKEN.findall(text))


def truncate_tokens(
    text: str, limit: int, *, encoding_name: str = "unicode-word-v1"
) -> str:
    if encoding_name != "unicode-word-v1":
        raise ValueError(f"Unsupported offline token encoding: {encoding_name}")
    if limit <= 0:
        return ""
    matches = list(_TOKEN.finditer(text))
    if len(matches) <= limit:
        return text
    return text[: matches[limit - 1].end()]
