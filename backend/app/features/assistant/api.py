"""HTTP adapter owned by the assistant feature."""

from app.features.assistant.api_ask import router

routers = (router,)

__all__ = ["routers"]
