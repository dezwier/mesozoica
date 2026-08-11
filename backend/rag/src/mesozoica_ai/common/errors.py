"""Typed failures for the RAG toolkit."""


class AiError(Exception):
    """Base class for expected toolkit failures."""


class ConfigurationError(AiError, ValueError):
    """Raised when settings are invalid."""


class SourceFetchError(AiError):
    """Raised when an external document source cannot be retrieved."""


class RateLimitedError(SourceFetchError):
    """Raised when a source returns HTTP 429 and the caller should stop cleanly."""

    def __init__(
        self,
        source: str,
        *,
        retry_after: str | None = None,
        partial_documents: list | None = None,
    ) -> None:
        self.source = source
        self.retry_after = retry_after
        self.partial_documents = list(partial_documents or [])
        detail = f"{source} returned HTTP 429 Too Many Requests"
        if retry_after:
            detail = f"{detail} (Retry-After: {retry_after})"
        super().__init__(detail)


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


class EmbeddingProviderError(AiError):
    """Raised when Azure OpenAI embeddings stay unavailable after retries."""


# Compatibility aliases used by moved private modules during redesign.
KnowledgeBaseConfigurationError = ConfigurationError
KnowledgeBaseError = AiError
RagConfigurationError = ConfigurationError
RagError = AiError
