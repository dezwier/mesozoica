"""Typed failures for the RAG toolkit."""


class AiError(Exception):
    """Base class for expected toolkit failures."""


class ConfigurationError(AiError, ValueError):
    """Raised when settings are invalid."""


class SourceFetchError(AiError):
    """Raised when an external document source cannot be retrieved."""


class IndexCompatibilityError(AiError):
    """Raised when an existing Azure Search index is unsafe to use."""


class BatchWriteError(AiError):
    """Raised after retryable batch writes are exhausted."""

    def __init__(self, operation: str, failed_keys: list[str]) -> None:
        self.operation = operation
        self.failed_keys = failed_keys
        super().__init__(f"{operation} failed for keys: {', '.join(failed_keys)}")


class InsufficientEvidenceError(AiError):
    """Raised when retrieval or prompting cannot satisfy evidence requirements."""


class StructuredOutputError(AiError):
    """Raised when model output fails schema validation."""


class CitationError(AiError):
    """Raised when output cites evidence that was not supplied."""


# Compatibility aliases used by moved private modules during redesign.
KnowledgeBaseConfigurationError = ConfigurationError
KnowledgeBaseError = AiError
RagConfigurationError = ConfigurationError
RagError = AiError
