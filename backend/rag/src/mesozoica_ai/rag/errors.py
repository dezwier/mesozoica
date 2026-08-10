"""Typed structured-generation failures."""


class RagError(Exception):
    """Base class for expected generation failures."""


class RagConfigurationError(RagError, ValueError):
    """Raised when generation settings are invalid."""


class InsufficientEvidenceError(RagError):
    """Raised when no usable evidence fits the prompt."""


class StructuredOutputError(RagError):
    """Raised when model output fails schema validation."""


class CitationError(RagError):
    """Raised when output cites evidence that was not supplied."""
