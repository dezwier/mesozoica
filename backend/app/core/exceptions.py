"""Application-level exceptions mapped to HTTP responses in app_factory."""


class MesozoicaException(Exception):
    """Base exception for domain errors."""


class NotFoundError(MesozoicaException):
    """Resource not found."""


class ValidationError(MesozoicaException):
    """Invalid input or business rule violation."""
