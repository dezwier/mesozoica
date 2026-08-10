"""Typed knowledge-base failures."""


class KnowledgeBaseError(Exception):
    """Base class for expected knowledge-base failures."""


class KnowledgeBaseConfigurationError(KnowledgeBaseError, ValueError):
    """Raised when knowledge-base settings are invalid."""


class IndexCompatibilityError(KnowledgeBaseError):
    """Raised when an existing Azure Search index is unsafe to use."""


class BatchWriteError(KnowledgeBaseError):
    """Raised after retryable batch writes are exhausted."""

    def __init__(self, operation: str, failed_keys: list[str]) -> None:
        self.operation = operation
        self.failed_keys = failed_keys
        super().__init__(f"{operation} failed for keys: {', '.join(failed_keys)}")


class InsufficientEvidenceError(KnowledgeBaseError):
    """Raised when retrieval cannot satisfy its evidence policy."""
